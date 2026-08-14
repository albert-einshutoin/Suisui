use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    process,
    sync::atomic::{AtomicU64, Ordering},
};

use fastembed::{
    InitOptionsUserDefined, Pooling, TextEmbedding, TokenizerFiles, UserDefinedEmbeddingModel,
};

const MAX_TEXT_BYTES: u64 = 64 * 1024;
const MAX_MODEL_BYTES: u64 = 400 * 1024 * 1024;
const EXPECTED_DIMENSIONS: usize = 384;
#[cfg(any(test, not(unix)))]
const MODEL_FILES: [&str; 5] = [
    "model.onnx",
    "tokenizer.json",
    "config.json",
    "special_tokens_map.json",
    "tokenizer_config.json",
];
const TEMPORARY_ATTEMPTS: u64 = 128;
static TEMPORARY_SEQUENCE: AtomicU64 = AtomicU64::new(0);

type AppResult<T> = Result<T, HelperError>;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct HelperError(&'static str);

impl HelperError {
    const INVALID_REQUEST: Self = Self("invalid request");
    const INPUT_TOO_LARGE: Self = Self("input is too large");
    const INPUT_EMPTY: Self = Self("input is empty");
    const INPUT_INVALID: Self = Self("input is invalid");
    const MODEL_INVALID: Self = Self("model is invalid");
    const EMBEDDING_FAILED: Self = Self("embedding failed");
    const OUTPUT_FAILED: Self = Self("output failed");
}

impl std::fmt::Display for HelperError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.0)
    }
}

impl std::error::Error for HelperError {}

trait EmbeddingEngine {
    fn embed(&mut self, text: &str) -> AppResult<Vec<f32>>;
}

struct Request {
    model_files: ModelFiles,
    text: String,
    output: OutputTarget,
}

#[cfg(unix)]
struct OutputTarget {
    parent: File,
    name: std::ffi::OsString,
}

#[cfg(not(unix))]
struct OutputTarget {
    path: PathBuf,
}

fn run_from<I>(arguments: I) -> AppResult<()>
where
    I: IntoIterator<Item = String>,
{
    let request = parse_request(arguments)?;
    let mut engine = FastEmbedEngine::load(request.model_files)?;
    write_embedding_to_target(&mut engine, &request.text, &request.output)
}

#[cfg(test)]
fn write_embedding<E: EmbeddingEngine>(engine: &mut E, text: &str, output: &Path) -> AppResult<()> {
    let output = validate_output(output)?;
    write_embedding_to_target(engine, text, &output)
}

fn write_embedding_to_target<E: EmbeddingEngine>(
    engine: &mut E,
    text: &str,
    output: &OutputTarget,
) -> AppResult<()> {
    validate_text(text)?;
    let values = engine.embed(text)?;
    validate_embedding(&values)?;
    write_atomically(output, embedding_json(&values).as_bytes())
}

fn parse_request<I>(arguments: I) -> AppResult<Request>
where
    I: IntoIterator<Item = String>,
{
    let mut arguments = arguments.into_iter();
    let mut model_dir = None;
    let mut text_file = None;
    let mut output = None;

    while let Some(flag) = arguments.next() {
        let value = arguments.next().ok_or(HelperError::INVALID_REQUEST)?;
        match flag.as_str() {
            "--model-dir" => set_once(&mut model_dir, value)?,
            "--text-file" => set_once(&mut text_file, value)?,
            "--output" => set_once(&mut output, value)?,
            _ => return Err(HelperError::INVALID_REQUEST),
        }
    }

    let model_dir = PathBuf::from(model_dir.ok_or(HelperError::INVALID_REQUEST)?);
    let model_files = load_model_files(&model_dir)?;
    let text = read_text(PathBuf::from(
        text_file.ok_or(HelperError::INVALID_REQUEST)?,
    ))?;
    let output = validate_output(&PathBuf::from(output.ok_or(HelperError::INVALID_REQUEST)?))?;

    Ok(Request {
        model_files,
        text,
        output,
    })
}

fn set_once(slot: &mut Option<String>, value: String) -> AppResult<()> {
    if slot.replace(value).is_some() {
        return Err(HelperError::INVALID_REQUEST);
    }
    Ok(())
}

struct FastEmbedEngine {
    model: TextEmbedding,
}

impl FastEmbedEngine {
    fn load(files: ModelFiles) -> AppResult<Self> {
        let model = UserDefinedEmbeddingModel::new(
            files.model,
            TokenizerFiles {
                tokenizer_file: files.tokenizer,
                config_file: files.config,
                special_tokens_map_file: files.special_tokens_map,
                tokenizer_config_file: files.tokenizer_config,
            },
        )
        .with_pooling(Pooling::Mean);
        let model =
            TextEmbedding::try_new_from_user_defined(model, InitOptionsUserDefined::default())
                .map_err(|_| HelperError::MODEL_INVALID)?;
        Ok(Self { model })
    }
}

impl EmbeddingEngine for FastEmbedEngine {
    fn embed(&mut self, text: &str) -> AppResult<Vec<f32>> {
        let embeddings = self
            .model
            .embed([text], None)
            .map_err(|_| HelperError::EMBEDDING_FAILED)?;
        let mut embeddings = embeddings.into_iter();
        let embedding = embeddings.next().ok_or(HelperError::EMBEDDING_FAILED)?;
        if embeddings.next().is_some() {
            return Err(HelperError::EMBEDDING_FAILED);
        }
        Ok(embedding)
    }
}

struct ModelFiles {
    model: Vec<u8>,
    tokenizer: Vec<u8>,
    config: Vec<u8>,
    special_tokens_map: Vec<u8>,
    tokenizer_config: Vec<u8>,
}

fn load_model_files(model_dir: &Path) -> AppResult<ModelFiles> {
    #[cfg(unix)]
    {
        let model_dir = open_existing_directory(model_dir, HelperError::MODEL_INVALID)?;
        load_model_files_from_directory(&model_dir)
    }

    #[cfg(not(unix))]
    {
        validate_model_dir(model_dir)?;
        load_model_files_from_paths(model_dir)
    }
}

#[cfg(unix)]
fn load_model_files_from_directory(model_dir: &File) -> AppResult<ModelFiles> {
    // UserDefinedEmbeddingModel owns these buffers; enforcing the aggregate cap
    // before construction bounds the helper's peak untrusted-model allocation.
    let mut remaining = MAX_MODEL_BYTES;
    let mut read = |name: &str| {
        let bytes = read_bounded_file_from_directory(
            model_dir,
            name,
            remaining,
            HelperError::MODEL_INVALID,
            HelperError::MODEL_INVALID,
        )?;
        if bytes.is_empty() {
            return Err(HelperError::MODEL_INVALID);
        }
        remaining = remaining
            .checked_sub(bytes.len() as u64)
            .ok_or(HelperError::MODEL_INVALID)?;
        Ok(bytes)
    };

    Ok(ModelFiles {
        model: read("model.onnx")?,
        tokenizer: read("tokenizer.json")?,
        config: read("config.json")?,
        special_tokens_map: read("special_tokens_map.json")?,
        tokenizer_config: read("tokenizer_config.json")?,
    })
}

#[cfg(not(unix))]
fn load_model_files_from_paths(model_dir: &Path) -> AppResult<ModelFiles> {
    // UserDefinedEmbeddingModel owns these buffers; enforcing the aggregate cap
    // before construction bounds the helper's peak untrusted-model allocation.
    let mut remaining = MAX_MODEL_BYTES;
    let mut read = |name: &str| {
        let bytes = read_bounded_file(
            &model_dir.join(name),
            remaining,
            HelperError::MODEL_INVALID,
            HelperError::MODEL_INVALID,
        )?;
        if bytes.is_empty() {
            return Err(HelperError::MODEL_INVALID);
        }
        remaining = remaining
            .checked_sub(bytes.len() as u64)
            .ok_or(HelperError::MODEL_INVALID)?;
        Ok(bytes)
    };

    Ok(ModelFiles {
        model: read("model.onnx")?,
        tokenizer: read("tokenizer.json")?,
        config: read("config.json")?,
        special_tokens_map: read("special_tokens_map.json")?,
        tokenizer_config: read("tokenizer_config.json")?,
    })
}

#[cfg(not(unix))]
fn validate_model_dir(path: &Path) -> AppResult<()> {
    validate_existing_directory(path, HelperError::MODEL_INVALID)?;
    let mut total = 0_u64;
    for name in MODEL_FILES {
        let metadata = validate_regular_file(&path.join(name), HelperError::MODEL_INVALID)?;
        if metadata.len() == 0 {
            return Err(HelperError::MODEL_INVALID);
        }
        total = total
            .checked_add(metadata.len())
            .ok_or(HelperError::MODEL_INVALID)?;
        if total > MAX_MODEL_BYTES {
            return Err(HelperError::MODEL_INVALID);
        }
    }
    Ok(())
}

fn read_text(path: PathBuf) -> AppResult<String> {
    validate_regular_file(&path, HelperError::INPUT_INVALID)?;
    let bytes = read_bounded_file(
        &path,
        MAX_TEXT_BYTES,
        HelperError::INPUT_TOO_LARGE,
        HelperError::INPUT_INVALID,
    )?;
    let text = String::from_utf8(bytes).map_err(|_| HelperError::INPUT_INVALID)?;
    validate_text(&text)?;
    Ok(text)
}

fn validate_text(text: &str) -> AppResult<()> {
    if text.is_empty() {
        return Err(HelperError::INPUT_EMPTY);
    }
    if text.len() as u64 > MAX_TEXT_BYTES {
        return Err(HelperError::INPUT_TOO_LARGE);
    }
    Ok(())
}

fn read_bounded_file(
    path: &Path,
    maximum: u64,
    too_large: HelperError,
    read_error: HelperError,
) -> AppResult<Vec<u8>> {
    read_bounded_open_file(
        open_regular_file(path, read_error)?,
        maximum,
        too_large,
        read_error,
    )
}

fn read_bounded_open_file(
    file: File,
    maximum: u64,
    too_large: HelperError,
    read_error: HelperError,
) -> AppResult<Vec<u8>> {
    let capacity = usize::try_from(maximum.min(64 * 1024)).map_err(|_| too_large)?;
    let mut bytes = Vec::with_capacity(capacity);
    file.take(maximum.saturating_add(1))
        .read_to_end(&mut bytes)
        .map_err(|_| read_error)?;
    if bytes.len() as u64 > maximum {
        return Err(too_large);
    }
    Ok(bytes)
}

fn open_regular_file(path: &Path, error: HelperError) -> AppResult<File> {
    #[cfg(unix)]
    let file = {
        use std::os::unix::fs::OpenOptionsExt;

        OpenOptions::new()
            .read(true)
            // Check the final path component at open time: metadata alone has
            // a gap in which an attacker can replace a checked file with a link.
            // O_NONBLOCK keeps a raced FIFO/device replacement from blocking
            // before the post-open fstat below rejects non-regular files.
            .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
            .open(path)
            .map_err(|_| error)?
    };
    #[cfg(not(unix))]
    let file = File::open(path).map_err(|_| error)?;

    if !file.metadata().map_err(|_| error)?.file_type().is_file() {
        return Err(error);
    }
    Ok(file)
}

#[cfg(unix)]
fn read_bounded_file_from_directory(
    directory: &File,
    name: &str,
    maximum: u64,
    too_large: HelperError,
    read_error: HelperError,
) -> AppResult<Vec<u8>> {
    read_bounded_open_file(
        open_regular_file_at(directory, name, read_error)?,
        maximum,
        too_large,
        read_error,
    )
}

#[cfg(unix)]
fn open_regular_file_at(directory: &File, name: &str, error: HelperError) -> AppResult<File> {
    use std::{
        ffi::CString,
        os::unix::io::{AsRawFd, FromRawFd},
    };

    let name = CString::new(name).map_err(|_| error)?;
    // SAFETY: directory owns the FD and name is a NUL-terminated basename.
    // O_NONBLOCK rejects a raced FIFO/device without blocking before fstat.
    let descriptor = unsafe {
        libc::openat(
            directory.as_raw_fd(),
            name.as_ptr(),
            libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_CLOEXEC,
        )
    };
    if descriptor < 0 {
        return Err(error);
    }
    // SAFETY: openat returned a new owned descriptor on success.
    let file = unsafe { File::from_raw_fd(descriptor) };
    if !file.metadata().map_err(|_| error)?.file_type().is_file() {
        return Err(error);
    }
    Ok(file)
}

fn validate_regular_file(path: &Path, error: HelperError) -> AppResult<fs::Metadata> {
    validate_absolute(path, error)?;
    let parent = path.parent().ok_or(error)?;
    validate_existing_directory(parent, error)?;
    let metadata = fs::symlink_metadata(path).map_err(|_| error)?;
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return Err(error);
    }
    Ok(metadata)
}

fn validate_output(path: &Path) -> AppResult<OutputTarget> {
    validate_absolute(path, HelperError::OUTPUT_FAILED)?;
    let parent = path.parent().ok_or(HelperError::OUTPUT_FAILED)?;
    let name = path.file_name().ok_or(HelperError::OUTPUT_FAILED)?;

    #[cfg(unix)]
    {
        let parent = open_existing_directory(parent, HelperError::OUTPUT_FAILED)?;
        ensure_output_missing(&parent, name)?;
        Ok(OutputTarget {
            parent,
            name: name.to_os_string(),
        })
    }

    #[cfg(not(unix))]
    {
        validate_existing_directory(parent, HelperError::OUTPUT_FAILED)?;
        match fs::symlink_metadata(path) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(OutputTarget {
                path: path.to_path_buf(),
            }),
            _ => Err(HelperError::OUTPUT_FAILED),
        }
    }
}

#[cfg(unix)]
fn open_existing_directory(path: &Path, error: HelperError) -> AppResult<File> {
    use std::os::unix::fs::OpenOptionsExt;

    validate_absolute(path, error)?;
    let directory = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW)
        .open(path)
        .map_err(|_| error)?;
    if !directory
        .metadata()
        .map_err(|_| error)?
        .file_type()
        .is_dir()
    {
        return Err(error);
    }
    Ok(directory)
}

#[cfg(unix)]
fn ensure_output_missing(parent: &File, name: &std::ffi::OsStr) -> AppResult<()> {
    use std::{ffi::CString, mem::MaybeUninit, os::unix::ffi::OsStrExt, os::unix::io::AsRawFd};

    let name = CString::new(name.as_bytes()).map_err(|_| HelperError::OUTPUT_FAILED)?;
    let mut metadata = MaybeUninit::<libc::stat>::uninit();
    // SAFETY: the directory FD and NUL-terminated name remain valid throughout
    // this fstatat call; AT_SYMLINK_NOFOLLOW rejects an existing link as output.
    let result = unsafe {
        libc::fstatat(
            parent.as_raw_fd(),
            name.as_ptr(),
            metadata.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    };
    if result == 0 {
        return Err(HelperError::OUTPUT_FAILED);
    }
    if std::io::Error::last_os_error().kind() == std::io::ErrorKind::NotFound {
        Ok(())
    } else {
        Err(HelperError::OUTPUT_FAILED)
    }
}

fn validate_existing_directory(path: &Path, error: HelperError) -> AppResult<()> {
    validate_absolute(path, error)?;
    let metadata = fs::symlink_metadata(path).map_err(|_| error)?;
    if metadata.file_type().is_symlink() || !metadata.file_type().is_dir() {
        return Err(error);
    }
    Ok(())
}

fn validate_absolute(path: &Path, error: HelperError) -> AppResult<()> {
    if !path.is_absolute()
        || path
            .components()
            .any(|component| matches!(component, Component::ParentDir))
    {
        return Err(error);
    }
    Ok(())
}

fn validate_embedding(values: &[f32]) -> AppResult<()> {
    if values.len() != EXPECTED_DIMENSIONS || values.iter().any(|value| !value.is_finite()) {
        return Err(HelperError::EMBEDDING_FAILED);
    }
    Ok(())
}

fn embedding_json(values: &[f32]) -> String {
    let mut output = format!(
        "{{\"schemaVersion\":1,\"providerID\":\"local-fastembed\",\"dimensions\":{},\"values\":[",
        values.len()
    );
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&value.to_string());
    }
    output.push_str("]}");
    output
}

#[cfg(unix)]
fn write_atomically(output: &OutputTarget, bytes: &[u8]) -> AppResult<()> {
    use std::{ffi::CString, os::unix::io::AsRawFd};

    let sequence = TEMPORARY_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    for attempt in 0..TEMPORARY_ATTEMPTS {
        let temporary = CString::new(format!(
            ".suisui-embedding-{}-{sequence}-{attempt}.tmp",
            process::id()
        ))
        .map_err(|_| HelperError::OUTPUT_FAILED)?;
        let file = match create_output_temporary(output.parent.as_raw_fd(), &temporary) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return Err(HelperError::OUTPUT_FAILED),
        };
        let mut published = false;
        let result = (|| {
            let mut file = file;
            file.write_all(bytes)
                .map_err(|_| HelperError::OUTPUT_FAILED)?;
            file.sync_all().map_err(|_| HelperError::OUTPUT_FAILED)?;
            drop(file);
            publish_no_replace(output.parent.as_raw_fd(), &temporary, &output.name)?;
            published = true;
            output
                .parent
                .sync_all()
                .map_err(|_| HelperError::OUTPUT_FAILED)
        })();
        if result.is_err() && !published {
            // A post-publish fsync failure must not remove a name another
            // writer creates after rename has moved our temporary away.
            let _ = unsafe { libc::unlinkat(output.parent.as_raw_fd(), temporary.as_ptr(), 0) };
        }
        return result;
    }
    Err(HelperError::OUTPUT_FAILED)
}

#[cfg(unix)]
fn create_output_temporary(
    directory: libc::c_int,
    name: &std::ffi::CString,
) -> std::io::Result<File> {
    use std::os::unix::io::FromRawFd;

    // SAFETY: directory is owned by OutputTarget, and name is a valid
    // NUL-terminated basename. O_EXCL ensures collided temporaries are untouched.
    let descriptor = unsafe {
        libc::openat(
            directory,
            name.as_ptr(),
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            0o600,
        )
    };
    if descriptor < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        // SAFETY: openat returned a new owned descriptor on success.
        Ok(unsafe { File::from_raw_fd(descriptor) })
    }
}

#[cfg(target_os = "macos")]
fn publish_no_replace(
    directory: libc::c_int,
    temporary: &std::ffi::CString,
    output: &std::ffi::OsStr,
) -> AppResult<()> {
    use std::{ffi::CString, os::unix::ffi::OsStrExt};

    let output = CString::new(output.as_bytes()).map_err(|_| HelperError::OUTPUT_FAILED)?;
    // macOS RENAME_EXCL preserves a racing output while atomically renaming
    // the fsynced temporary into the requested entry of the same fixed directory.
    // SAFETY: CString guarantees NUL termination without interior NUL bytes;
    // both pointers remain valid for this call, and the owned directory FD
    // plus RENAME_EXCL are the documented macOS renameatx_np constants.
    let result = unsafe {
        libc::renameatx_np(
            directory,
            temporary.as_ptr(),
            directory,
            output.as_ptr(),
            libc::RENAME_EXCL,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(HelperError::OUTPUT_FAILED)
    }
}

#[cfg(target_os = "linux")]
fn publish_no_replace(
    directory: libc::c_int,
    temporary: &std::ffi::CString,
    output: &std::ffi::OsStr,
) -> AppResult<()> {
    use std::{ffi::CString, os::unix::ffi::OsStrExt};

    let output = CString::new(output.as_bytes()).map_err(|_| HelperError::OUTPUT_FAILED)?;
    // SAFETY: both names are NUL-terminated basenames resolved only below the
    // owned directory FD; RENAME_NOREPLACE prevents an existing output overwrite.
    let result = unsafe {
        libc::renameat2(
            directory,
            temporary.as_ptr(),
            directory,
            output.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(HelperError::OUTPUT_FAILED)
    }
}

#[cfg(all(unix, not(any(target_os = "macos", target_os = "linux"))))]
fn publish_no_replace(
    directory: libc::c_int,
    temporary: &std::ffi::CString,
    output: &std::ffi::OsStr,
) -> AppResult<()> {
    use std::{ffi::CString, os::unix::ffi::OsStrExt};

    let output = CString::new(output.as_bytes()).map_err(|_| HelperError::OUTPUT_FAILED)?;
    // SAFETY: linkat atomically creates the destination name below the fixed
    // directory FD, then the source temporary is unlinked from that same FD.
    let linked =
        unsafe { libc::linkat(directory, temporary.as_ptr(), directory, output.as_ptr(), 0) };
    if linked != 0 {
        return Err(HelperError::OUTPUT_FAILED);
    }
    // SAFETY: temporary is the just-linked basename below the owned directory FD.
    if unsafe { libc::unlinkat(directory, temporary.as_ptr(), 0) } == 0 {
        Ok(())
    } else {
        Err(HelperError::OUTPUT_FAILED)
    }
}

#[cfg(not(unix))]
fn write_atomically(output: &OutputTarget, bytes: &[u8]) -> AppResult<()> {
    let parent = output.path.parent().ok_or(HelperError::OUTPUT_FAILED)?;
    let sequence = TEMPORARY_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    for attempt in 0..TEMPORARY_ATTEMPTS {
        let temporary = parent.join(format!(
            ".suisui-embedding-{}-{sequence}-{attempt}.tmp",
            process::id()
        ));
        let file = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
        {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return Err(HelperError::OUTPUT_FAILED),
        };
        let result = (|| {
            let mut file = file;
            file.write_all(bytes)
                .map_err(|_| HelperError::OUTPUT_FAILED)?;
            file.sync_all().map_err(|_| HelperError::OUTPUT_FAILED)?;
            drop(file);
            fs::hard_link(&temporary, &output.path).map_err(|_| HelperError::OUTPUT_FAILED)?;
            fs::remove_file(&temporary).map_err(|_| HelperError::OUTPUT_FAILED)?;
            File::open(parent)
                .and_then(|directory| directory.sync_all())
                .map_err(|_| HelperError::OUTPUT_FAILED)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        return result;
    }
    Err(HelperError::OUTPUT_FAILED)
}

pub fn main_entry() {
    let result = env::args_os()
        .skip(1)
        .map(|argument| {
            argument
                .into_string()
                .map_err(|_| HelperError::INVALID_REQUEST)
        })
        .collect::<AppResult<Vec<_>>>()
        .and_then(run_from);
    if let Err(error) = result {
        eprintln!("embedding helper: {error}");
        process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::{Path, PathBuf},
        process,
        sync::atomic::{AtomicU64, Ordering},
    };

    #[cfg(unix)]
    use std::{
        ffi::CString, os::unix::ffi::OsStrExt, os::unix::fs::PermissionsExt, sync::mpsc, thread,
        time::Duration,
    };

    use super::{
        EmbeddingEngine, HelperError, MAX_TEXT_BYTES, parse_request, validate_embedding,
        write_embedding,
    };

    static SCRATCH_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    struct Scratch(PathBuf);

    impl Scratch {
        fn new(label: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "suisui-embedding-helper-{label}-{}-{}",
                process::id(),
                SCRATCH_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).expect("scratch directory");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    struct FixedEngine;

    impl EmbeddingEngine for FixedEngine {
        fn embed(&mut self, text: &str) -> Result<Vec<f32>, HelperError> {
            assert_eq!(text, "private input");
            let mut values = vec![0.5; super::EXPECTED_DIMENSIONS];
            values[1] = -1.0;
            Ok(values)
        }
    }

    #[test]
    fn writes_finite_embedding_as_contract_json() {
        let scratch = Scratch::new("contract");
        let output = scratch.path().join("embedding.json");

        write_embedding(&mut FixedEngine, "private input", &output).expect("output");

        assert_eq!(
            fs::read_to_string(&output).expect("output JSON"),
            format!(
                "{{\"schemaVersion\":1,\"providerID\":\"local-fastembed\",\"dimensions\":384,\"values\":[{}]}}",
                std::iter::once("0.5")
                    .chain(std::iter::once("-1"))
                    .chain(std::iter::repeat_n("0.5", super::EXPECTED_DIMENSIONS - 2))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        );
        assert!(
            fs::read_dir(scratch.path())
                .expect("output directory")
                .all(|entry| !entry
                    .expect("directory entry")
                    .file_name()
                    .to_string_lossy()
                    .contains(".tmp"))
        );
        #[cfg(unix)]
        assert_eq!(
            fs::metadata(&output)
                .expect("output metadata")
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }

    #[test]
    fn refuses_to_replace_existing_output() {
        let scratch = Scratch::new("existing-output");
        let output = scratch.path().join("embedding.json");
        fs::write(&output, "keep").expect("existing output");

        let result = write_embedding(&mut FixedEngine, "private input", &output);

        assert_eq!(result, Err(HelperError::OUTPUT_FAILED));
        assert_eq!(fs::read_to_string(output).expect("existing output"), "keep");
    }

    #[test]
    fn rejects_empty_and_non_finite_embeddings() {
        assert_eq!(validate_embedding(&[]), Err(HelperError::EMBEDDING_FAILED));
        assert_eq!(
            validate_embedding(&vec![0.0; super::EXPECTED_DIMENSIONS - 1]),
            Err(HelperError::EMBEDDING_FAILED)
        );
        assert_eq!(
            validate_embedding(&{
                let mut values = vec![0.0; super::EXPECTED_DIMENSIONS];
                values[0] = f32::NAN;
                values
            }),
            Err(HelperError::EMBEDDING_FAILED)
        );
        assert_eq!(
            validate_embedding(&{
                let mut values = vec![0.0; super::EXPECTED_DIMENSIONS];
                values[0] = f32::INFINITY;
                values
            }),
            Err(HelperError::EMBEDDING_FAILED)
        );
    }

    #[test]
    fn preserves_output_created_during_embedding() {
        struct RacingEngine(PathBuf);

        impl EmbeddingEngine for RacingEngine {
            fn embed(&mut self, _text: &str) -> Result<Vec<f32>, HelperError> {
                fs::write(&self.0, "racing output").expect("racing output");
                Ok(vec![0.0; super::EXPECTED_DIMENSIONS])
            }
        }

        let scratch = Scratch::new("output-race");
        let output = scratch.path().join("embedding.json");
        let result = write_embedding(&mut RacingEngine(output.clone()), "private input", &output);

        assert_eq!(result, Err(HelperError::OUTPUT_FAILED));
        assert_eq!(
            fs::read_to_string(output).expect("racing output"),
            "racing output"
        );
    }

    #[cfg(unix)]
    #[test]
    fn output_parent_swap_does_not_redirect_a_validated_write() {
        use std::os::unix::fs::symlink;

        struct ParentSwappingEngine {
            parent: PathBuf,
            retained_parent: PathBuf,
            replacement: PathBuf,
        }

        impl EmbeddingEngine for ParentSwappingEngine {
            fn embed(&mut self, _text: &str) -> Result<Vec<f32>, HelperError> {
                fs::rename(&self.parent, &self.retained_parent).expect("retain validated parent");
                symlink(&self.replacement, &self.parent).expect("replace parent with symlink");
                Ok(vec![0.0; super::EXPECTED_DIMENSIONS])
            }
        }

        let scratch = Scratch::new("output-parent-swap");
        let parent = scratch.path().join("output-parent");
        let retained_parent = scratch.path().join("validated-parent");
        let replacement = scratch.path().join("replacement-parent");
        fs::create_dir(&parent).expect("output parent");
        fs::create_dir(&replacement).expect("replacement parent");
        let output = parent.join("embedding.json");

        write_embedding(
            &mut ParentSwappingEngine {
                parent,
                retained_parent: retained_parent.clone(),
                replacement: replacement.clone(),
            },
            "private input",
            &output,
        )
        .expect("output remains in validated parent");

        assert!(retained_parent.join("embedding.json").is_file());
        assert!(!replacement.join("embedding.json").exists());
    }

    #[cfg(unix)]
    #[test]
    fn model_parent_swap_does_not_replace_validated_generation() {
        use std::os::unix::fs::symlink;

        let scratch = Scratch::new("model-parent-swap");
        let model = scratch.path().join("model");
        let retained_model = scratch.path().join("validated-model");
        let replacement = scratch.path().join("replacement-model");
        write_model_generation(&model, "original");
        write_model_generation(&replacement, "replacement");

        let model_directory = super::open_existing_directory(&model, HelperError::MODEL_INVALID)
            .expect("open original model");
        fs::rename(&model, &retained_model).expect("retain original model");
        symlink(&replacement, &model).expect("replace model parent with symlink");

        assert_eq!(
            model_generation(
                super::load_model_files_from_directory(&model_directory).expect("load fixed model"),
            ),
            "original"
        );
    }

    #[cfg(unix)]
    fn write_model_generation(directory: &Path, generation: &str) {
        fs::create_dir(directory).expect("model directory");
        for name in super::MODEL_FILES {
            fs::write(directory.join(name), format!("{generation}:{name}")).expect("model asset");
        }
    }

    #[cfg(unix)]
    fn model_generation(files: super::ModelFiles) -> String {
        let files = [
            files.model,
            files.tokenizer,
            files.config,
            files.special_tokens_map,
            files.tokenizer_config,
        ];
        let generation = std::str::from_utf8(&files[0])
            .expect("model bytes")
            .split_once(':')
            .expect("generation separator")
            .0
            .to_owned();
        assert!(
            files.iter().all(|file| {
                String::from_utf8_lossy(file).starts_with(&format!("{generation}:"))
            })
        );
        generation
    }

    #[test]
    fn rejects_oversized_text_before_model_loading() {
        let scratch = Scratch::new("limit");
        let model_dir = scratch.path().join("model");
        fs::create_dir(&model_dir).expect("model directory");
        for name in super::MODEL_FILES {
            fs::write(model_dir.join(name), "placeholder").expect("model file");
        }
        let text_file = scratch.path().join("input.txt");
        fs::write(&text_file, vec![b'x'; MAX_TEXT_BYTES as usize + 1]).expect("text file");

        let result = parse_request([
            "--model-dir".to_owned(),
            model_dir.to_string_lossy().into_owned(),
            "--text-file".to_owned(),
            text_file.to_string_lossy().into_owned(),
            "--output".to_owned(),
            scratch
                .path()
                .join("output.json")
                .to_string_lossy()
                .into_owned(),
        ]);

        assert_eq!(result.err(), Some(HelperError::INPUT_TOO_LARGE));
    }

    #[test]
    fn rejects_empty_required_model_files() {
        let scratch = Scratch::new("empty-model-file");
        let model_dir = scratch.path().join("model");
        fs::create_dir(&model_dir).expect("model directory");
        for name in super::MODEL_FILES {
            fs::write(model_dir.join(name), "placeholder").expect("model file");
        }
        fs::write(model_dir.join("config.json"), []).expect("empty model file");

        let result = parse_request([
            "--model-dir".to_owned(),
            model_dir.to_string_lossy().into_owned(),
            "--text-file".to_owned(),
            scratch
                .path()
                .join("input.txt")
                .to_string_lossy()
                .into_owned(),
            "--output".to_owned(),
            scratch
                .path()
                .join("output.json")
                .to_string_lossy()
                .into_owned(),
        ]);

        assert_eq!(result.err(), Some(HelperError::MODEL_INVALID));
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symlinked_model_files() {
        use std::os::unix::fs::symlink;

        let scratch = Scratch::new("symlink");
        let model_dir = scratch.path().join("model");
        fs::create_dir(&model_dir).expect("model directory");
        for name in super::MODEL_FILES {
            fs::write(model_dir.join(name), "placeholder").expect("model file");
        }
        let real_model = scratch.path().join("real-model.onnx");
        fs::write(&real_model, "placeholder").expect("real model");
        fs::remove_file(model_dir.join("model.onnx")).expect("replace model");
        symlink(&real_model, model_dir.join("model.onnx")).expect("model symlink");

        let result = parse_request([
            "--model-dir".to_owned(),
            model_dir.to_string_lossy().into_owned(),
            "--text-file".to_owned(),
            scratch
                .path()
                .join("input.txt")
                .to_string_lossy()
                .into_owned(),
            "--output".to_owned(),
            scratch
                .path()
                .join("output.json")
                .to_string_lossy()
                .into_owned(),
        ]);

        assert_eq!(result.err(), Some(HelperError::MODEL_INVALID));
    }

    #[cfg(unix)]
    #[test]
    fn rejects_fifo_input_model_and_voice_paths_without_blocking() {
        let scratch = Scratch::new("fifo");
        for (name, error) in [
            ("input.fifo", HelperError::INPUT_INVALID),
            ("model.onnx", HelperError::MODEL_INVALID),
            ("voice.fifo", HelperError::INPUT_INVALID),
        ] {
            let path = scratch.path().join(name);
            create_fifo(&path);
            assert_fifo_open_is_bounded(path, error);
        }
    }

    #[cfg(unix)]
    fn create_fifo(path: &Path) {
        let path = CString::new(path.as_os_str().as_bytes()).expect("FIFO path");
        // SAFETY: CString provides a NUL-terminated path that remains valid
        // for this call; 0600 grants only the current user FIFO access.
        assert_eq!(
            unsafe { libc::mkfifo(path.as_ptr(), 0o600) },
            0,
            "create FIFO"
        );
    }

    #[cfg(unix)]
    fn assert_fifo_open_is_bounded(path: PathBuf, error: HelperError) {
        let (sender, receiver) = mpsc::channel();
        thread::spawn(move || {
            sender
                .send(super::open_regular_file(&path, error))
                .expect("report FIFO result");
        });

        match receiver.recv_timeout(Duration::from_secs(1)) {
            Ok(Err(actual)) => assert_eq!(actual, error),
            Ok(Ok(_)) => panic!("FIFO open unexpectedly succeeded"),
            Err(_) => panic!("FIFO open must fail before waiting for a writer"),
        }
    }
}

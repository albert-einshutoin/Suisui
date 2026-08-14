use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{self, BufWriter, Read, Write},
    path::{Path, PathBuf},
    process,
};

use kokoro_en::KokoroTts;

const SAMPLE_RATE: u32 = 24_000;
const MAX_PROMPT_CHARACTERS: usize = 280;
const MAX_PROMPT_BYTES: u64 = (MAX_PROMPT_CHARACTERS * 4) as u64;
const MAX_MODEL_BYTES: u64 = 400 * 1024 * 1024;
const MAX_VOICE_BYTES: u64 = 2 * 1024 * 1024;
const JAPANESE_PARITY_ERROR: &str = "日本語パリティ未達なので本番利用不可";
const USAGE: &str = "usage: suisui-kokoro-helper --model <absolute .onnx> --voices <absolute dir or .bin> --text-file <absolute UTF-8> --language en --voice <safe a|b id> --output <absolute .wav>";

type AppResult<T> = Result<T, String>;

struct Request {
    model: PathBuf,
    voices: PathBuf,
    text: String,
    voice: String,
    output: PathBuf,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("BLOCKER: Kokoro helper: {error}");
        process::exit(1);
    }
}

fn run() -> AppResult<()> {
    let request = parse_request(env::args().skip(1))?;
    configure_dependency_environment(&request.voice);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .build()
        .map_err(|_| "Kokoro async runtime could not be started".to_owned())?;
    runtime.block_on(synthesize(request))
}

async fn synthesize(request: Request) -> AppResult<()> {
    let tts = KokoroTts::new(&request.model, &request.voices)
        .await
        .map_err(|_| "Kokoro model or voice pack could not be loaded".to_owned())?;
    let (audio, _) = tts
        .synth(&request.text, &request.voice)
        .await
        .map_err(|_| "Kokoro synthesis failed".to_owned())?;

    write_pcm16_wav(&request.output, &audio)
}

fn configure_dependency_environment(voice: &str) {
    // The process is still single-threaded here, before Tokio exists. Pinning these
    // variables keeps G2P offline and prevents inherited trace or executable hooks.
    unsafe {
        env::set_var("KOKORO_ESPEAK_NG", "0");
        env::set_var("KOKORO_G2P_SEGMENT_ESPEAK", "0");
        env::set_var(
            "KOKORO_G2P_LANG",
            if voice.starts_with('b') { "b" } else { "a" },
        );
        for key in [
            "KOKORO_ESPEAK_NG_BIN",
            "KOKORO_G2P_LEXICON",
            "KOKORO_G2P_TRACE",
            "KOKORO_G2P_LEGACY",
            "KOKORO_G2P_REQUIRE_ESPEAK",
        ] {
            env::remove_var(key);
        }
    }
}

fn parse_request<I>(arguments: I) -> AppResult<Request>
where
    I: IntoIterator<Item = String>,
{
    let mut arguments = arguments.into_iter();
    let mut model = None;
    let mut voices = None;
    let mut text_file = None;
    let mut language = None;
    let mut voice = None;
    let mut output = None;

    while let Some(flag) = arguments.next() {
        let value = arguments
            .next()
            .ok_or_else(|| format!("missing value for {flag}; {USAGE}"))?;
        match flag.as_str() {
            "--model" => set_once(&mut model, value, "--model")?,
            "--voices" => set_once(&mut voices, value, "--voices")?,
            "--text-file" => set_once(&mut text_file, value, "--text-file")?,
            "--language" => set_once(&mut language, value, "--language")?,
            "--voice" => set_once(&mut voice, value, "--voice")?,
            "--output" => set_once(&mut output, value, "--output")?,
            _ => return Err(format!("unknown argument {flag}; {USAGE}")),
        }
    }

    let language = required(language, "--language")?;
    validate_language(&language)?;
    let voice = required(voice, "--voice")?;
    validate_voice(&voice)?;

    let model = validate_file(
        PathBuf::from(required(model, "--model")?),
        "Kokoro model",
        Some("onnx"),
        MAX_MODEL_BYTES,
    )?;
    let voices = validate_voices(PathBuf::from(required(voices, "--voices")?), &voice)?;
    let text = read_prompt(PathBuf::from(required(text_file, "--text-file")?))?;
    let output = validate_output(PathBuf::from(required(output, "--output")?))?;

    Ok(Request {
        model,
        voices,
        text,
        voice,
        output,
    })
}

fn set_once(slot: &mut Option<String>, value: String, flag: &str) -> AppResult<()> {
    if slot.replace(value).is_some() {
        return Err(format!("{flag} may only be provided once"));
    }
    Ok(())
}

fn required(value: Option<String>, flag: &str) -> AppResult<String> {
    value.ok_or_else(|| format!("missing required argument {flag}; {USAGE}"))
}

fn validate_language(value: &str) -> AppResult<()> {
    if value == "ja" {
        return Err(JAPANESE_PARITY_ERROR.to_owned());
    }
    if value != "en" {
        return Err("only English is supported by this Rust PoC".to_owned());
    }
    Ok(())
}

fn validate_voice(value: &str) -> AppResult<()> {
    let mut characters = value.chars();
    let Some(prefix) = characters.next() else {
        return Err("Kokoro voice id is missing".to_owned());
    };
    if !matches!(prefix, 'a' | 'b') {
        return Err("English Kokoro voice id must start with a or b".to_owned());
    }
    if !value
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
    {
        return Err(
            "Kokoro voice id must contain only ASCII letters, numbers, underscore, or hyphen"
                .to_owned(),
        );
    }
    Ok(())
}

fn read_prompt(path: PathBuf) -> AppResult<String> {
    let path = validate_file(path, "Kokoro text file", None, MAX_PROMPT_BYTES)?;
    let mut bytes = Vec::with_capacity(MAX_PROMPT_BYTES as usize + 1);
    File::open(path)
        .map_err(|_| "Kokoro text file could not be opened".to_owned())?
        .take(MAX_PROMPT_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "Kokoro text file could not be read".to_owned())?;
    if bytes.len() as u64 > MAX_PROMPT_BYTES {
        return Err(format!(
            "Kokoro prompts are limited to {MAX_PROMPT_CHARACTERS} characters"
        ));
    }
    let text =
        String::from_utf8(bytes).map_err(|_| "Kokoro text file must be valid UTF-8".to_owned())?;
    if text.trim().is_empty() {
        return Err("Kokoro prompt is missing or empty".to_owned());
    }
    if text.chars().count() > MAX_PROMPT_CHARACTERS {
        return Err(format!(
            "Kokoro prompts are limited to {MAX_PROMPT_CHARACTERS} characters"
        ));
    }
    Ok(text)
}

fn validate_file(
    path: PathBuf,
    label: &str,
    extension: Option<&str>,
    maximum_bytes: u64,
) -> AppResult<PathBuf> {
    validate_absolute(&path, label)?;
    let metadata = fs::symlink_metadata(&path).map_err(|_| format!("{label} is missing"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(format!("{label} must be a regular file"));
    }
    if metadata.len() == 0 {
        return Err(format!("{label} must not be empty"));
    }
    if metadata.len() > maximum_bytes {
        return Err(format!("{label} exceeds the size limit"));
    }
    if let Some(extension) = extension
        && path.extension().and_then(|value| value.to_str()) != Some(extension)
    {
        return Err(format!("{label} must use the .{extension} extension"));
    }
    Ok(path)
}

fn validate_voices(path: PathBuf, voice: &str) -> AppResult<PathBuf> {
    validate_absolute(&path, "Kokoro voices")?;
    let metadata =
        fs::symlink_metadata(&path).map_err(|_| "Kokoro voices are missing".to_owned())?;
    if metadata.file_type().is_symlink() {
        return Err("Kokoro voices must not be a symbolic link".to_owned());
    }
    if metadata.is_dir() {
        return validate_file(
            path.join(format!("{voice}.bin")),
            "Selected Kokoro voice",
            Some("bin"),
            MAX_VOICE_BYTES,
        );
    }
    if metadata.is_file() && path.extension().and_then(|value| value.to_str()) == Some("bin") {
        let path = validate_file(path, "Kokoro voice file", Some("bin"), MAX_VOICE_BYTES)?;
        if path.file_stem().and_then(|value| value.to_str()) != Some(voice) {
            return Err("Kokoro voice file name must match --voice".to_owned());
        }
        return Ok(path);
    }
    Err("Kokoro voices must be a directory or a .bin file".to_owned())
}

fn validate_output(path: PathBuf) -> AppResult<PathBuf> {
    validate_absolute(&path, "Kokoro output")?;
    if path.extension().and_then(|value| value.to_str()) != Some("wav") {
        return Err("Kokoro output must use the .wav extension".to_owned());
    }
    let parent = path
        .parent()
        .ok_or_else(|| "Kokoro output has no parent directory".to_owned())?;
    let parent_metadata = fs::symlink_metadata(parent)
        .map_err(|_| "Kokoro output parent directory is missing".to_owned())?;
    if parent_metadata.file_type().is_symlink() || !parent_metadata.is_dir() {
        return Err("Kokoro output parent must be a regular directory".to_owned());
    }
    if let Ok(metadata) = fs::symlink_metadata(&path)
        && (metadata.file_type().is_symlink() || !metadata.is_file())
    {
        return Err("Kokoro output must be a regular file when it already exists".to_owned());
    }
    Ok(path)
}

fn validate_absolute(path: &Path, label: &str) -> AppResult<()> {
    if !path.is_absolute() {
        return Err(format!("{label} path must be absolute"));
    }
    if path.as_os_str().is_empty() {
        return Err(format!("{label} path is empty"));
    }
    Ok(())
}

fn write_pcm16_wav(path: &Path, audio: &[f32]) -> AppResult<()> {
    if audio.is_empty() {
        return Err("Kokoro synthesis produced no audio".to_owned());
    }
    let sample_bytes = audio
        .len()
        .checked_mul(2)
        .and_then(|size| u32::try_from(size).ok())
        .ok_or_else(|| "Kokoro audio is too large to write as WAV".to_owned())?;
    let temporary_path = temporary_output_path(path)?;
    write_wav_file(&temporary_path, sample_bytes, audio)?;

    // Keep the partial file invisible to the app: a same-directory rename is atomic.
    if fs::rename(&temporary_path, path).is_err() {
        let _ = fs::remove_file(&temporary_path);
        return Err("Kokoro WAV could not be finalized".to_owned());
    }
    Ok(())
}

fn temporary_output_path(path: &Path) -> AppResult<PathBuf> {
    let parent = path
        .parent()
        .ok_or_else(|| "Kokoro output has no parent directory".to_owned())?;
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "Kokoro output file name must be valid UTF-8".to_owned())?;
    Ok(parent.join(format!(".{name}.{}.tmp", process::id())))
}

fn write_wav_file(path: &Path, sample_bytes: u32, audio: &[f32]) -> AppResult<()> {
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|_| "Kokoro WAV temporary file could not be created".to_owned())?;
    let mut writer = BufWriter::new(file);
    let result = (|| -> io::Result<()> {
        write_wav_header(&mut writer, sample_bytes)?;
        for &sample in audio {
            let pcm = (sample.clamp(-1.0, 1.0) * f32::from(i16::MAX)).round() as i16;
            writer.write_all(&pcm.to_le_bytes())?;
        }
        writer.flush()?;
        writer.get_ref().sync_all()
    })();
    if result.is_err() {
        drop(writer);
        let _ = fs::remove_file(path);
        return Err("Kokoro WAV could not be written".to_owned());
    }
    Ok(())
}

fn write_wav_header(writer: &mut impl Write, sample_bytes: u32) -> io::Result<()> {
    let byte_rate = SAMPLE_RATE * 2;
    let riff_size = 36_u32
        .checked_add(sample_bytes)
        .ok_or_else(|| io::Error::other("WAV is too large"))?;
    writer.write_all(b"RIFF")?;
    writer.write_all(&riff_size.to_le_bytes())?;
    writer.write_all(b"WAVEfmt ")?;
    writer.write_all(&16_u32.to_le_bytes())?;
    writer.write_all(&1_u16.to_le_bytes())?;
    writer.write_all(&1_u16.to_le_bytes())?;
    writer.write_all(&SAMPLE_RATE.to_le_bytes())?;
    writer.write_all(&byte_rate.to_le_bytes())?;
    writer.write_all(&2_u16.to_le_bytes())?;
    writer.write_all(&16_u16.to_le_bytes())?;
    writer.write_all(b"data")?;
    writer.write_all(&sample_bytes.to_le_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn validate_language_should_reject_japanese_until_parity_exists() {
        let error = validate_language("ja").unwrap_err();

        assert_eq!(error, JAPANESE_PARITY_ERROR);
    }

    #[test]
    fn validate_voice_should_accept_english_voice_ids() {
        let result = validate_voice("af_heart");

        assert!(result.is_ok(), "voice should be accepted: {result:?}");
    }

    #[test]
    fn validate_voice_should_reject_non_english_prefixes() {
        let error = validate_voice("jf_alpha").unwrap_err();

        assert_eq!(error, "English Kokoro voice id must start with a or b");
    }

    #[test]
    fn validate_voices_should_return_only_the_selected_file() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let selected = directory.join("af_heart.bin");
        fs::write(&selected, b"voice").unwrap();
        fs::write(directory.join("af_alloy.bin"), b"other voice").unwrap();

        let result = validate_voices(directory.clone(), "af_heart").unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(result, selected);
    }

    #[test]
    fn read_prompt_should_reject_files_larger_than_the_utf8_limit() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let prompt = directory.join("prompt.txt");
        fs::write(&prompt, vec![b'a'; MAX_PROMPT_BYTES as usize + 1]).unwrap();

        let error = read_prompt(prompt).unwrap_err();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(error, "Kokoro text file exceeds the size limit");
    }

    #[test]
    fn write_pcm16_wav_should_create_24khz_mono_pcm_file() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let output = directory.join("speech.wav");

        write_pcm16_wav(&output, &[0.0, 1.0, -1.0]).unwrap();
        let wav = fs::read(&output).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(&wav[..4], b"RIFF");
        assert_eq!(&wav[22..24], &1_u16.to_le_bytes());
        assert_eq!(&wav[24..28], &SAMPLE_RATE.to_le_bytes());
        assert_eq!(&wav[34..36], &16_u16.to_le_bytes());
        assert_eq!(&wav[40..44], &6_u32.to_le_bytes());
        assert_eq!(wav.len(), 50);
    }

    #[test]
    fn write_pcm16_wav_should_reject_empty_audio() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let output = directory.join("speech.wav");

        let error = write_pcm16_wav(&output, &[]).unwrap_err();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(error, "Kokoro synthesis produced no audio");
        assert!(!output.exists());
    }

    #[test]
    fn write_pcm16_wav_should_replace_an_existing_regular_file() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let output = directory.join("speech.wav");
        fs::write(&output, b"stale").unwrap();

        write_pcm16_wav(&output, &[0.0]).unwrap();
        let wav = fs::read(&output).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(&wav[..4], b"RIFF");
    }

    #[test]
    fn write_pcm16_wav_should_not_remove_a_temporary_file_it_did_not_create() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let output = directory.join("speech.wav");
        let temporary = temporary_output_path(&output).unwrap();
        fs::write(&temporary, b"owned elsewhere").unwrap();

        let error = write_pcm16_wav(&output, &[0.0]).unwrap_err();
        let temporary_contents = fs::read(&temporary).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(error, "Kokoro WAV temporary file could not be created");
        assert_eq!(temporary_contents, b"owned elsewhere");
    }

    fn unique_test_directory() -> PathBuf {
        env::temp_dir().join(format!(
            "suisui-kokoro-helper-{}-{}-{}",
            process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
            NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed)
        ))
    }
}

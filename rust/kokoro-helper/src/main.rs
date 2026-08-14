use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{self, BufWriter, Read, Write},
    mem::size_of,
    path::{Path, PathBuf},
    process,
};

use ort::{inputs, session::Session, value::Tensor};

const SAMPLE_RATE: u32 = 24_000;
const MAX_TOKEN_BYTES: u64 = 4 * 1024;
// Kokoro v1.0 supports 510 content tokens; this CLI receives the model-ready
// sequence with the required leading and trailing padding ids already present.
const MAX_PADDED_TOKENS: usize = 512;
// The published v1.0 vocabulary uses ids 0...177, with 0 reserved for padding.
const MAX_TOKEN_ID: i64 = 177;
const MAX_MODEL_BYTES: u64 = 400 * 1024 * 1024;
const MAX_VOICE_BYTES: u64 = 2 * 1024 * 1024;
const STYLE_VALUES: usize = 256;
const JAPANESE_PARITY_ERROR: &str = "日本語パリティ未達なので本番利用不可";
const USAGE: &str = "usage: suisui-kokoro-helper --model <absolute .onnx> --voices <absolute dir or .bin> --tokens-file <absolute token ids> --language en --voice <safe a|b id> --output <absolute .wav>";

type AppResult<T> = Result<T, String>;

struct Request {
    model: PathBuf,
    voices: PathBuf,
    tokens: Vec<i64>,
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
    synthesize(request)
}

fn synthesize(request: Request) -> AppResult<()> {
    let style = read_voice_style(&request.voices, request.tokens.len())?;
    let token_count = request.tokens.len();
    let token_tensor = Tensor::from_array(([1, token_count], request.tokens))
        .map_err(|_| "Kokoro token tensor could not be created".to_owned())?;
    let style_tensor = Tensor::from_array(([1, STYLE_VALUES], style))
        .map_err(|_| "Kokoro style tensor could not be created".to_owned())?;
    let speed_tensor = Tensor::from_array(([1], vec![1.0_f32]))
        .map_err(|_| "Kokoro speed tensor could not be created".to_owned())?;
    let mut session = Session::builder()
        .and_then(|builder| builder.commit_from_file(&request.model))
        .map_err(|_| "Kokoro model could not be loaded".to_owned())?;
    let outputs = session
        .run(inputs![
            "input_ids" => token_tensor,
            "style" => style_tensor,
            "speed" => speed_tensor,
        ])
        .map_err(|_| "Kokoro inference failed".to_owned())?;
    let waveform = outputs
        .get("waveform")
        .ok_or_else(|| "Kokoro model has no waveform output".to_owned())?;
    let (_, audio) = waveform
        .try_extract_tensor::<f32>()
        .map_err(|_| "Kokoro waveform output is invalid".to_owned())?;

    write_pcm16_wav(&request.output, audio)
}

fn parse_request<I>(arguments: I) -> AppResult<Request>
where
    I: IntoIterator<Item = String>,
{
    let mut arguments = arguments.into_iter();
    let mut model = None;
    let mut voices = None;
    let mut tokens_file = None;
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
            "--tokens-file" => set_once(&mut tokens_file, value, "--tokens-file")?,
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
    let tokens = read_tokens(PathBuf::from(required(tokens_file, "--tokens-file")?))?;
    let output = validate_output(PathBuf::from(required(output, "--output")?))?;

    Ok(Request {
        model,
        voices,
        tokens,
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

fn read_tokens(path: PathBuf) -> AppResult<Vec<i64>> {
    let path = validate_file(path, "Kokoro tokens file", None, MAX_TOKEN_BYTES)?;
    let bytes = read_bounded(&path, MAX_TOKEN_BYTES, "Kokoro tokens file")?;
    let text = String::from_utf8(bytes)
        .map_err(|_| "Kokoro tokens file must be valid UTF-8".to_owned())?;
    let tokens = text
        .split_ascii_whitespace()
        .map(|value| {
            value
                .parse::<i64>()
                .map_err(|_| "Kokoro tokens must be decimal integers".to_owned())
        })
        .collect::<AppResult<Vec<_>>>()?;
    if !(3..=MAX_PADDED_TOKENS).contains(&tokens.len()) {
        return Err(format!(
            "Kokoro token count must be between 3 and {MAX_PADDED_TOKENS}"
        ));
    }
    if tokens.first() != Some(&0) || tokens.last() != Some(&0) {
        return Err("Kokoro tokens must start and end with 0".to_owned());
    }
    if tokens[1..tokens.len() - 1]
        .iter()
        .any(|token| !(1..=MAX_TOKEN_ID).contains(token))
    {
        return Err(format!(
            "Kokoro inner token ids must be between 1 and {MAX_TOKEN_ID}"
        ));
    }
    Ok(tokens)
}

fn read_voice_style(path: &Path, token_count: usize) -> AppResult<Vec<f32>> {
    let bytes = read_bounded(path, MAX_VOICE_BYTES, "Kokoro voice file")?;
    let frame_bytes = STYLE_VALUES * size_of::<f32>();
    if bytes.len() % frame_bytes != 0 || token_count < 3 {
        return Err("Kokoro voice file has an invalid raw f32 shape".to_owned());
    }
    // The ONNX asset contract indexes voice rows by the unpadded token count;
    // this CLI requires both surrounding pad ids in the supplied sequence.
    let offset = (token_count - 2)
        .checked_mul(frame_bytes)
        .filter(|offset| offset + frame_bytes <= bytes.len())
        .ok_or_else(|| "Kokoro voice file has no style for this token count".to_owned())?;
    let style = bytes[offset..offset + frame_bytes]
        .chunks_exact(size_of::<f32>())
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect::<Vec<_>>();
    if style.iter().any(|value| !value.is_finite()) {
        return Err("Kokoro voice style contains a non-finite value".to_owned());
    }
    Ok(style)
}

fn read_bounded(path: &Path, maximum_bytes: u64, label: &str) -> AppResult<Vec<u8>> {
    let mut bytes = Vec::with_capacity(maximum_bytes.min(64 * 1024) as usize);
    File::open(path)
        .map_err(|_| format!("{label} could not be opened"))?
        .take(maximum_bytes + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| format!("{label} could not be read"))?;
    if bytes.len() as u64 > maximum_bytes {
        return Err(format!("{label} exceeds the size limit"));
    }
    Ok(bytes)
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
    if audio.iter().any(|sample| !sample.is_finite()) {
        return Err("Kokoro synthesis produced non-finite audio".to_owned());
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
    const CONTRACT_MODEL: &[u8] = &[
        0x08, 0x08, 0x12, 0x0c, 0x53, 0x75, 0x69, 0x73, 0x75, 0x69, 0x20, 0x74, 0x65, 0x73, 0x74,
        0x73, 0x3a, 0xa4, 0x01, 0x0a, 0x1b, 0x0a, 0x05, 0x73, 0x74, 0x79, 0x6c, 0x65, 0x12, 0x08,
        0x77, 0x61, 0x76, 0x65, 0x66, 0x6f, 0x72, 0x6d, 0x22, 0x08, 0x49, 0x64, 0x65, 0x6e, 0x74,
        0x69, 0x74, 0x79, 0x12, 0x16, 0x73, 0x75, 0x69, 0x73, 0x75, 0x69, 0x2d, 0x6b, 0x6f, 0x6b,
        0x6f, 0x72, 0x6f, 0x2d, 0x63, 0x6f, 0x6e, 0x74, 0x72, 0x61, 0x63, 0x74, 0x5a, 0x21, 0x0a,
        0x09, 0x69, 0x6e, 0x70, 0x75, 0x74, 0x5f, 0x69, 0x64, 0x73, 0x12, 0x14, 0x0a, 0x12, 0x08,
        0x07, 0x12, 0x0e, 0x0a, 0x02, 0x08, 0x01, 0x0a, 0x08, 0x12, 0x06, 0x74, 0x6f, 0x6b, 0x65,
        0x6e, 0x73, 0x5a, 0x18, 0x0a, 0x05, 0x73, 0x74, 0x79, 0x6c, 0x65, 0x12, 0x0f, 0x0a, 0x0d,
        0x08, 0x01, 0x12, 0x09, 0x0a, 0x02, 0x08, 0x01, 0x0a, 0x03, 0x08, 0x80, 0x02, 0x5a, 0x13,
        0x0a, 0x05, 0x73, 0x70, 0x65, 0x65, 0x64, 0x12, 0x0a, 0x0a, 0x08, 0x08, 0x01, 0x12, 0x04,
        0x0a, 0x02, 0x08, 0x01, 0x62, 0x1b, 0x0a, 0x08, 0x77, 0x61, 0x76, 0x65, 0x66, 0x6f, 0x72,
        0x6d, 0x12, 0x0f, 0x0a, 0x0d, 0x08, 0x01, 0x12, 0x09, 0x0a, 0x02, 0x08, 0x01, 0x0a, 0x03,
        0x08, 0x80, 0x02, 0x42, 0x04, 0x0a, 0x00, 0x10, 0x12,
    ];

    #[test]
    fn validate_language_should_reject_japanese_until_parity_exists() {
        let error = validate_language("ja").unwrap_err();

        assert_eq!(error, JAPANESE_PARITY_ERROR);
    }

    #[test]
    fn synthesize_should_preserve_the_kokoro_onnx_io_contract() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let model = directory.join("contract.onnx");
        let voice = directory.join("af_heart.bin");
        let output = directory.join("speech.wav");
        fs::write(&model, CONTRACT_MODEL).unwrap();
        let mut voice_bytes = vec![0_u8; STYLE_VALUES * size_of::<f32>() * 3];
        let selected_frame = STYLE_VALUES * size_of::<f32>();
        for sample in voice_bytes[selected_frame..].chunks_exact_mut(size_of::<f32>()) {
            sample.copy_from_slice(&0.25_f32.to_le_bytes());
        }
        fs::write(&voice, voice_bytes).unwrap();

        synthesize(Request {
            model,
            voices: voice,
            tokens: vec![0, 1, 0],
            output: output.clone(),
        })
        .unwrap();
        let wav = fs::read(&output).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(&wav[..4], b"RIFF");
        assert_eq!(&wav[40..44], &(STYLE_VALUES as u32 * 2).to_le_bytes());
        assert!(wav[44..].iter().any(|byte| *byte != 0));
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
    fn read_tokens_should_accept_bounded_v10_ids() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let tokens = directory.join("tokens.txt");
        fs::write(&tokens, b"0 50 83 54 156 57 135 0").unwrap();

        let result = read_tokens(tokens).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(result, [0, 50, 83, 54, 156, 57, 135, 0]);
    }

    #[test]
    fn read_tokens_should_accept_510_content_tokens_plus_padding() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let tokens = directory.join("tokens.txt");
        let padded = std::iter::once("0")
            .chain(std::iter::repeat_n("1", 510))
            .chain(std::iter::once("0"))
            .collect::<Vec<_>>()
            .join(" ");
        fs::write(&tokens, padded).unwrap();

        let result = read_tokens(tokens).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(result.len(), 512);
    }

    #[test]
    fn read_tokens_should_reject_files_larger_than_the_input_limit() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let tokens = directory.join("tokens.txt");
        fs::write(&tokens, vec![b'1'; MAX_TOKEN_BYTES as usize + 1]).unwrap();

        let error = read_tokens(tokens).unwrap_err();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(error, "Kokoro tokens file exceeds the size limit");
    }

    #[test]
    fn read_voice_style_should_select_the_token_count_frame() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let voice = directory.join("af_heart.bin");
        let mut bytes = vec![0_u8; STYLE_VALUES * size_of::<f32>() * 3];
        let offset = STYLE_VALUES * size_of::<f32>();
        bytes[offset..offset + 4].copy_from_slice(&0.5_f32.to_le_bytes());
        fs::write(&voice, bytes).unwrap();

        let style = read_voice_style(&voice, 3).unwrap();
        let _ = fs::remove_dir_all(&directory);

        assert_eq!(style.len(), STYLE_VALUES);
        assert_eq!(style[0], 0.5);
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

        assert_eq!(error, "Kokoro synthesis produced no audio");
        assert!(!output.exists());
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn write_pcm16_wav_should_reject_non_finite_audio() {
        let directory = unique_test_directory();
        fs::create_dir_all(&directory).unwrap();
        let output = directory.join("speech.wav");

        let error = write_pcm16_wav(&output, &[f32::NAN]).unwrap_err();

        assert_eq!(error, "Kokoro synthesis produced non-finite audio");
        assert!(!output.exists());
        let _ = fs::remove_dir_all(&directory);
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

use std::{
    env, fs,
    path::PathBuf,
    process::{self, Command},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

const HELPER: &str = env!("CARGO_BIN_EXE_suisui-kokoro-helper");
static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(0);

#[test]
fn japanese_language_is_rejected_before_model_loading() {
    let output = Command::new(HELPER)
        .args([
            "--model",
            "/missing/model.onnx",
            "--voices",
            "/missing/voices",
            "--text-file",
            "/missing/prompt.txt",
            "--language",
            "ja",
            "--voice",
            "jf_alpha",
            "--output",
            "/tmp/speech.wav",
        ])
        .output()
        .unwrap();

    assert!(
        !output.status.success()
            && String::from_utf8_lossy(&output.stderr).contains("BLOCKER:")
            && String::from_utf8_lossy(&output.stderr)
                .contains("日本語パリティ未達なので本番利用不可")
    );
}

#[test]
fn rejected_prompt_is_not_written_to_standard_streams() {
    let directory = unique_test_directory();
    fs::create_dir_all(&directory).unwrap();
    let model = directory.join("model.onnx");
    let voice = directory.join("af_heart.bin");
    let prompt = directory.join("prompt.txt");
    fs::write(&model, b"model").unwrap();
    fs::write(&voice, b"voice").unwrap();
    let secret_prompt = "PROMPT_MUST_NOT_APPEAR".repeat(20);
    fs::write(&prompt, &secret_prompt).unwrap();

    let output = Command::new(HELPER)
        .args([
            "--model",
            model.to_str().unwrap(),
            "--voices",
            voice.to_str().unwrap(),
            "--text-file",
            prompt.to_str().unwrap(),
            "--language",
            "en",
            "--voice",
            "af_heart",
            "--output",
            directory.join("speech.wav").to_str().unwrap(),
        ])
        .output()
        .unwrap();
    let _ = fs::remove_dir_all(&directory);
    let streams = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    assert!(!output.status.success() && !streams.contains(&secret_prompt));
}

fn unique_test_directory() -> PathBuf {
    env::temp_dir().join(format!(
        "suisui-kokoro-helper-cli-{}-{}-{}",
        process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
        NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed)
    ))
}

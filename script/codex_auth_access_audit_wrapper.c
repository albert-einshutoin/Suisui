#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static int build_sidecar_path(char *output, size_t output_size, const char *executable, const char *suffix) {
    int written = snprintf(output, output_size, "%s%s", executable, suffix);
    return written >= 0 && (size_t)written < output_size ? 0 : -1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Codex auth-access audit wrapper requires Codex arguments.\n");
        return 64;
    }

    char pid_path[PATH_MAX];
    char ready_path[PATH_MAX];
    char codex_path[PATH_MAX];
    if (build_sidecar_path(pid_path, sizeof(pid_path), argv[0], ".child-pid") != 0 ||
        build_sidecar_path(ready_path, sizeof(ready_path), argv[0], ".ready") != 0 ||
        build_sidecar_path(codex_path, sizeof(codex_path), argv[0], ".real-codex") != 0) {
        fprintf(stderr, "Codex auth-access audit wrapper path is too long.\n");
        return 64;
    }

    int pid_file = open(pid_path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR);
    if (pid_file < 0 || dprintf(pid_file, "%d\n", getpid()) < 0 || close(pid_file) != 0) {
        fprintf(stderr, "Codex auth-access audit wrapper could not publish its PID.\n");
        return 74;
    }

    // A native waiter avoids fs_usage's default shell-process exclusion. execv
    // then preserves this audited PID across the transition into the real Codex.
    const struct timespec poll_interval = {.tv_sec = 0, .tv_nsec = 50 * 1000 * 1000};
    for (int attempt = 0; attempt < 3600; attempt++) {
        if (access(ready_path, F_OK) == 0) {
            char **codex_argv = calloc((size_t)argc + 1, sizeof(char *));
            if (codex_argv == NULL) {
                fprintf(stderr, "Codex auth-access audit wrapper could not allocate arguments.\n");
                return 71;
            }
            codex_argv[0] = codex_path;
            for (int index = 1; index < argc; index++) {
                codex_argv[index] = argv[index];
            }
            execv(codex_path, codex_argv);
            fprintf(stderr, "Codex auth-access audit wrapper could not exec Codex: %s\n", strerror(errno));
            free(codex_argv);
            return 71;
        }
        if (errno != ENOENT) {
            fprintf(stderr, "Codex auth-access audit wrapper could not inspect its ready file.\n");
            return 74;
        }
        nanosleep(&poll_interval, NULL);
    }

    fprintf(stderr, "Codex auth-access audit wrapper timed out before tracing was ready.\n");
    return 75;
}

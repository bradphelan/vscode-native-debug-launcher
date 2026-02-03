#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

// Helper function to write to both stdout and log file
void dual_print(FILE *logFile, const char *format, ...) {
  va_list args;

  // Print to stdout
  va_start(args, format);
  vprintf(format, args);
  va_end(args);

  // Print to log file if open
  if (logFile) {
    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);
  }
}

int main(int argc, char *argv[]) {
  // Get output directory from environment variable
  FILE *logFile = NULL;
  char logPath[1024] = {0};
  const char *outputDir = getenv("E2E_TEST_OUTPUT_DIR");

  if (outputDir && strlen(outputDir) > 0) {
    snprintf(logPath, sizeof(logPath), "%s\\e2e-test-output.log", outputDir);
  } else {
    snprintf(logPath, sizeof(logPath), "e2e-test-output.log");
  }

  printf("📝 Output Log File: %s\n", logPath);

  logFile = fopen(logPath, "w");
  if (!logFile) {
    printf("ERROR: Could not create log file at: %s\n", logPath);
  }

  // Print to console and log file
  dual_print(logFile, "=================================\n");
  dual_print(logFile, "Hello World Debug Test Application\n");
  dual_print(logFile, "=================================\n\n");

  dual_print(logFile, "Process Info:\n");
#ifdef _WIN32
  dual_print(logFile, "  PID: %lu\n", GetCurrentProcessId());
#else
  dual_print(logFile, "  PID: %d\n", getpid());
#endif
  dual_print(logFile, "  Command Line Arguments: %d\n", argc);

  if (argc > 1) {
    dual_print(logFile, "  Arguments:\n");
    for (int i = 1; i < argc; i++) {
      dual_print(logFile, "    [%d]: %s\n", i, argv[i]);
    }
  } else {
    dual_print(logFile, "  (no arguments)\n");
  }

  dual_print(logFile, "\n");
  dual_print(logFile,
             "This application is a simple test for VS Code debugger.\n");
  dual_print(logFile, "You can:\n");
  dual_print(logFile, "  - Set breakpoints\n");
  dual_print(logFile, "  - Step through code\n");
  dual_print(logFile, "  - Inspect variables\n");
  dual_print(logFile, "\n");

  // Calculate something to debug
  int sum = 0;
  for (int i = 1; i <= 5; i++) {
    sum += i * 2;
    dual_print(logFile, "  Loop iteration %d: sum = %d\n", i, sum);
  }

  dual_print(logFile, "\n");
  dual_print(logFile, "Final Result: %d\n", sum);
  dual_print(logFile, "=================================\n");
  dual_print(logFile, "Application completed successfully!\n");
  dual_print(logFile, "=================================\n");

  // Write verification metadata (header + data)
  if (logFile) {
    fprintf(logFile, "\nE2E_TEST_OUTPUT\n");
    fprintf(logFile, "argc=%d\n", argc);

    // Write all arguments
    for (int i = 0; i < argc; i++) {
      fprintf(logFile, "argv[%d]=%s\n", i, argv[i]);
    }

    fprintf(logFile, "sum=%d\n", sum);
    fprintf(logFile, "status=SUCCESS\n");

    fclose(logFile);
  }

  return 0;
}

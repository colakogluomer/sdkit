#!/usr/bin/env bash
echo "required|java|install a JDK (see the build file for the version)"
echo "optional|mvn|brew install maven (not needed when the project ships ./mvnw)"
echo "optional|gradle|brew install gradle (not needed when the project ships ./gradlew)"
echo "optional|google-java-format|brew install google-java-format (post-edit formatting is skipped without it)"
echo "optional|ktlint|brew install ktlint (Kotlin post-edit formatting is skipped without it)"

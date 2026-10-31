#!/usr/bin/env bash
# exit 0 when $1 contains a Maven/Gradle build file that uses Spring Boot
[ -n "$(find "${1:-.}" -maxdepth 3 \( -name node_modules -o -name target -o -name build \) -prune -o \
  \( -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) -type f -print0 2>/dev/null |
  xargs -0 grep -lE 'org\.springframework\.boot|spring-boot' 2>/dev/null | head -1)" ]

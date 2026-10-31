#!/usr/bin/env bash
# exit 0 when $1 contains a Maven/Gradle build file (Java/Kotlin without Spring Boot; init probes spring-boot first)
[ -n "$(find "${1:-.}" -maxdepth 3 \( -name node_modules -o -name target -o -name build -o -name .git \) -prune -o \
  \( -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) -type f -print 2>/dev/null | head -1)" ]

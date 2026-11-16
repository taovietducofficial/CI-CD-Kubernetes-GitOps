# syntax=docker/dockerfile:1

# ---- build ----------------------------------------------------------------
# Base images are pinned by digest; Renovate bumps them with a PR.
FROM eclipse-temurin:21-jdk-noble@sha256:06c1f157dacf6b68198bd9a4186dd4c34ef24e65d7bbbe2a0cf8e62571ad38c9 AS build
WORKDIR /workspace

# Dependencies first so this layer is reused until the pom changes.
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q dependency:go-offline

COPY src src
# Tests already ran in CI (job "app"); the image build only packages.
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q package -DskipTests -Djacoco.skip=true \
 && java -Djarmode=tools -jar target/app.jar extract --layers --launcher --destination extracted

# ---- runtime --------------------------------------------------------------
# distroless: no shell, no package manager, runs as uid 65532.
FROM gcr.io/distroless/java21-debian12:nonroot@sha256:7e37784d94dccbf5ccb195c73b295f5ad00cd266512dfbac12eb9c3c28f8077d
WORKDIR /app

# Ordered from least to most frequently changing so pulls only fetch the app layer.
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./

# Already the base image's default; stated so scanners and readers don't have to know that.
USER 65532:65532
EXPOSE 8080 8081
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "org.springframework.boot.loader.launch.JarLauncher"]

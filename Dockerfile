# Environnement de build : SDK Android et Java de l'image cirruslabs, SDK
# Flutter remplace par la version officielle indiquee ci-dessous (l'image
# cirruslabs n'est plus publiee au-dela de 3.44.0). Pour monter de
# version : changer FLUTTER_VERSION et FLUTTER_SHA256 (cf.
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json),
# puis `docker compose build`.
FROM ghcr.io/cirruslabs/flutter:3.44.0

ARG FLUTTER_VERSION=3.47.5
ARG FLUTTER_SHA256=2132e990f236f8d22e7c6314b29a191a95b10d7cbcfec9b4e2e303d996652cbb

RUN rm -rf /sdks/flutter \
    && curl -fsSL -o /tmp/flutter.tar.xz \
       "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /sdks \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /sdks/flutter \
    && flutter config --no-analytics \
    && flutter precache --android --web \
    && flutter --version

# Composants Android telecharges sinon a chaque build release (conteneur
# jetable) : NDK de Flutter (FlutterExtension.ndkVersion), CMake, et
# plateformes compilees par les plugins.
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "ndk;28.2.13676358" "cmake;3.22.1" "platforms;android-34" "platforms;android-35" > /dev/null

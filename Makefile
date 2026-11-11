STORE_ID := tidy

.PHONY: run build clean test test-native

run:
	flutter pub get && flutter run

build:
	flutter pub get && flutter build apk --release

test:
	flutter analyze && flutter test

# Kotlin JVM tests (image metrics) with Flutter's JDK.
test-native:
	J=$$(flutter doctor -v 2>/dev/null | sed -n 's/.*Java binary at: \(.*\)\/bin\/java.*/\1/p' | head -1); \
	cd android && JAVA_HOME="$$J" ./gradlew :app:testDebugUnitTest

clean:
	flutter clean
	rm -rf dist

include store.mk

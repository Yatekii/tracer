cd rust
cbindgen src/lib.rs -c cbindgen.toml | grep -v \#include | uniq > target/bindings.h
cd ..
flutter pub run ffigen
@echo off
git submodule update --init External\src\openal
mkdir External\build\openal
pushd External\build\openal
cmake -DCMAKE_INSTALL_PREFIX=..\..\Windows\ -G "Visual Studio 17 2022" -A "x64" -Thost=x64 ..\..\src\openal
if "%1" == "" (cmake --build . --config Debug --target install) else (cmake --build . --config %1 --target install)
popd

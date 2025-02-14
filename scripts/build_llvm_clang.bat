git submodule update --init External/src/llvm
mkdir External\build\llvm
pushd External\build\llvm
cmake -DLLVM_ENABLE_DUMP=ON -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_INSTALL_UTILS=ON -DCMAKE_INSTALL_PREFIX=../../Windows  -DLLVM_TARGETS_TO_BUILD="AMDGPU;ARM;X86;AArch64;NVPTX" -DLLVM_ENABLE_PROJECTS="clang" -G "Visual Studio 17 2022" -A "x64" -Thost=x64 ../../src/llvm/llvm
if "%1" == "" (cmake --build . --config Debug --target install) else (cmake --build . --config %1 --target install)
popd


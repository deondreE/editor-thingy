{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    pkg-config
    cmake
    ninja
    odin
    glslang
    shaderc
  ];

  buildInputs = with pkgs; [
    # Vulkan
    vulkan-loader
    vulkan-headers
    vulkan-tools
    vulkan-validation-layers

    sdl3
  ];

  shellHook = ''
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${
      pkgs.lib.makeLibraryPath [
        pkgs.vulkan-loader
        pkgs.sdl3
      ]
    }"

    compile_shaders() {
      if [ -d "./core/shaders" ]; then 
        echo "Compiling Shaders..."
        for file in ./shaders/*{vert,frag,comp}; do 
          if [ -f "$file" ]; then
            glslangValidator -V "$file" -o "$file.spv"
            echo "Compiled: $file -> $file.spv"
          fi
        done
      else
        echo "No shaders directory found to compile."
      fi
    }

    export VK_LAYER_PATH="${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d"
    echo "--- Vulka & SDL Environment"
    echo "SDL3 version: $(pkg-config --modversion sdl3)"
    echo "Vulkan version: $(pkg-config --modversion vulkan)"
    echo "Shader Compiler: $(glslangValidator --version | head -n 1)"
    echo "Tip: Run 'compile_shaders' to rebuild your SPIR-V binaries."
  '';
}

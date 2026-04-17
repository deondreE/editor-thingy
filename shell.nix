{ pkgs ? import <nixpkgs> {} };

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    pkg-config
    cmake
    ninja
    odin
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

    export VK_LAYER_PATH="${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d"
    echo "--- Vulka & SDL Environment"
    echo "SDL3 version: $(pkg-config --modversion sdl3)"
    echo "Vulkan version: $(pkg-config --modversion vulkan)"
  '';
}

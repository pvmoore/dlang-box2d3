# Dlang Box2D 3.x Library

A Dlang wrapper for Box2D 3.x.

## Requirements
- Windows
- Dlang compiler https://dlang.org/
- Box2D 3.x (https://github.com/erincatto/box2d)
- dlang-vulkan https://github.com/pvmoore/dlang-vulkan
- dlanf common https://github.com/pvmoore/dlang-common
- dlang logging https://github.com/pvmoore/dlang-logging
- dlang maths https://github.com/pvmoore/dlang-maths

## Installation

git clone --recurse-submodules https://github.com/pvmoore/dlang-box2d3.git

```
cd box2d  
run build.bat or build.sh
```

This will create a build directiory containing the box2d library and samples.    

(Windows) Build the box2d solution in Release mode. This should create a box2d.lib file
in the box2d/build/src/Release directory which is references in the dub.sdl file.

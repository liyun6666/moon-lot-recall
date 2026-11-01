// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "liyun6666/moon-lot-recall"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/liyun6666/moon-lot-recall"

license = "Apache-2.0"

keywords = ["food-safety", "recall", "traceability", "lot", "audit"]

preferred_target = "js"

description = "Offline food-lot recall impact tracing with evidence paths and conservative diagnostics"

import {
    "moonbitlang/x@0.5.7",
}

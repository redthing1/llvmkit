#include <llvm/IR/Function.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/PassManager.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Plugins/PassPlugin.h>
#include <llvm/Support/raw_ostream.h>

using namespace llvm;

namespace {
struct CountIR : PassInfoMixin<CountIR> {
  PreservedAnalyses run(Module &module, ModuleAnalysisManager &) {
    unsigned functions = 0, instructions = 0;
    for (auto &function : module) {
      if (function.isDeclaration()) continue;
      ++functions;
      for (auto &block : function) instructions += block.size();
    }
    errs() << "[llvmkit-count] functions=" << functions
           << " instructions=" << instructions << '\n';
    return PreservedAnalyses::all();
  }
};

struct MarkInline : PassInfoMixin<MarkInline> {
  PreservedAnalyses run(Function &function, FunctionAnalysisManager &) {
    unsigned instructions = 0;
    for (auto &block : function) instructions += block.size();
    if (!function.isDeclaration() && instructions <= 10) {
      function.removeFnAttr(Attribute::NoInline);
      function.addFnAttr(Attribute::AlwaysInline);
    }
    return PreservedAnalyses::all();
  }
};

struct MarkLoaded : PassInfoMixin<MarkLoaded> {
  PreservedAnalyses run(Module &module, ModuleAnalysisManager &) {
    for (auto &function : module)
      if (!function.isDeclaration()) function.addFnAttr("llvmkit.plugin", "loaded");
    errs() << "[llvmkit-plugin] pipeline extension loaded\n";
    return PreservedAnalyses::all();
  }
};
}

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "LLVMKitPasses", LLVM_VERSION_STRING,
          [](PassBuilder &builder) {
            builder.registerPipelineParsingCallback(
                [](StringRef name, ModulePassManager &manager,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (name != "llvmkit-count") return false;
                  manager.addPass(CountIR());
                  return true;
                });
            builder.registerPipelineParsingCallback(
                [](StringRef name, FunctionPassManager &manager,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (name != "llvmkit-inline") return false;
                  manager.addPass(MarkInline());
                  return true;
                });
            builder.registerPipelineStartEPCallback(
                [](ModulePassManager &manager, OptimizationLevel) {
                  manager.addPass(MarkLoaded());
                });
          }};
}

#include <llvm/IR/LLVMContext.h>

int main() {
  llvm::LLVMContext context;
  return context.getMDKindID("llvmkit") == 0;
}

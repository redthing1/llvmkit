#include <remill/BC/Util.h>

int main() {
  // Calling an actual library function makes this a link and runtime check.
  return remill::FindSemanticsBitcodeFile("amd64").has_value() ? 0 : 1;
}

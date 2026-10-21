#include <LIEF/ELF.hpp>

#include <iostream>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  auto binary = LIEF::ELF::Parser::parse(argv[1]);
  if (!binary) {
    std::cerr << "LIEF could not parse " << argv[1] << '\n';
    return 1;
  }
  if (binary->segments().empty()) {
    std::cerr << "LIEF found no loadable image segments in " << argv[1] << '\n';
    return 1;
  }
  binary->write(argv[2]);
  std::cout << "LIEF ELF round-trip succeeded\n";
  return 0;
}

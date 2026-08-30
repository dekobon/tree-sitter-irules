from os.path import isdir, join
from platform import system

from setuptools import Extension, find_packages, setup
from setuptools.command.bdist_wheel import bdist_wheel
from setuptools.command.build import build


class Build(build):
    # Queries live at the repo root (`queries/irules/*.scm`), outside
    # the Python package source tree, so `package_data` cannot reach
    # them. Copy them into `build_lib` here; the wheel-builder then
    # includes them under `tree_sitter_irules/queries/irules/`.
    def run(self):
        if isdir("queries"):
            dest = join(self.build_lib, "tree_sitter_irules", "queries")
            self.copy_tree("queries", dest)
        super().run()


class BdistWheel(bdist_wheel):
    def get_tag(self):
        python, abi, platform = super().get_tag()
        if python.startswith("cp"):
            python, abi = "cp311", "abi3"
        return python, abi, platform


setup(
    packages=find_packages("bindings/python"),
    package_dir={"": "bindings/python"},
    package_data={
        "tree_sitter_irules": ["*.pyi", "py.typed"],
    },
    ext_package="tree_sitter_irules",
    ext_modules=[
        Extension(
            name="_binding",
            sources=[
                "bindings/python/tree_sitter_irules/binding.c",
                "src/parser.c",
                "src/scanner.c",
            ],
            extra_compile_args=(
                ["-std=c11"] if system() != 'Windows' else []
            ),
            define_macros=[
                ("Py_LIMITED_API", "0x030B0000"),
                ("PY_SSIZE_T_CLEAN", None)
            ],
            include_dirs=["src"],
            py_limited_api=True,
        )
    ],
    cmdclass={
        "build": Build,
        "bdist_wheel": BdistWheel
    },
    zip_safe=False
)

.PHONY: pdf clean c miru

PATH_MARKDOWN ?= "./main.md"
PATH_BUILD ?= "./build/"

# PATH_MARKDOWNのmarkdownファイルをPATH_BUILDでlatexに変換しpdfにbuildする.
# latexからpdfへのbuildにはtectonicを使う
pdf:
	mkdir -p ./build
	PATH_MARKDOWN=$(PATH_MARKDOWN) PATH_BUILD=$(PATH_BUILD) ./gen_pdf.py


clean:
	rm -rf ./build

c: clean


miru:
	open ./build/main.pdf


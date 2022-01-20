PAPERS = $(wildcard papers/*.md)
HTMLS  = $(subst papers/,html/,$(patsubst %.md,%.html,$(PAPERS)))
PDFS = $(subst papers/,pdfs/,$(patsubst %.md,%.pdf,$(PAPERS)))

default: $(HTMLS) $(PDFS)

html/%.html: papers/%.md header.html footer.html
	cat header.html > $@
	pandoc --from markdown-tex_math_dollars-raw_tex --to html --ascii $< >> $@
	cat footer.html >> $@

pdfs/%.pdf: papers/%.md
	pandoc \
		--variable geometry:margin=0.5in \
		--variable urlcolor:blue \
		--mathjax \
		--to pdf \
		--ascii $< >> $@

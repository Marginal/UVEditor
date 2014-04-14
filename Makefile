PROJECT = Marginal_UVEditor
VER=$(shell sed -nE 's/[[:space:]]*Version[[:space:]]*=[[:space:]]*"([[:digit:]]+\.[[:digit:]]+)"/\1/p' $(PROJECT).rb)

TARGET = $(PROJECT)_v$(VER).rbz

INSTALLDIR = /Library/Application\ Support/Google\ SketchUp\ 8/SketchUp/plugins

.PHONY:	all clean install

all:	$(TARGET)

clean:
	rm -f $(TARGET)

install:	$(TARGET)
	rm -rf $(INSTALLDIR)/$(PROJECT)
	unzip -o -d $(INSTALLDIR) $(TARGET)

$(PROJECT)_v$(VER).rbz:	$(PROJECT).rb $(PROJECT)/*.rb $(PROJECT)/Resources/*.html $(PROJECT)/Resources/*.js $(PROJECT)/Resources/*.png
# $(PROJECT)/Resources/*.css $(PROJECT)/Resources/??/*.html $(PROJECT)/Resources/??/*.strings
	rm -f $@
	zip -MM $@ $+

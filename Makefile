.PHONY: default install clean

default:
	echo "default"
	pmbootstrap init
	./setup.bash

install:
	echo "unused"

clean:
	rm -rf ~/.local/var/pmbootstrap

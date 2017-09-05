# $Id: Makefile,v 1.2 2016/05/17 22:25:18 hlein Exp $

TARGET_NORM_DIR=/usr/local/etc

# executable (mode 755) files to be installed
BIN_FILES=\
		ipt-count-trace		\
		mon-hosts					\

include ../common/rules.mk

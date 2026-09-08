MODULE   := pam_authelia_passkey.so
SRC      := pam_authelia_passkey.c
CFLAGS   := -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=2 -O2 -fPIC
LDFLAGS  := -shared -Wl,-z,relro,-z,now
LIBS     := -lpam

.PHONY: all clean verify-hardening

all: $(MODULE)

$(MODULE): $(SRC)
	gcc $(CFLAGS) $(LDFLAGS) -o $@ $< $(LIBS)

verify-hardening: $(MODULE)
	readelf -d $(MODULE) | grep -q BIND_NOW
	readelf -h $(MODULE) | grep -q 'Type:.*DYN'

clean:
	rm -f $(MODULE)

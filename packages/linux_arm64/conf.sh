	CC=musl-gcc \
./configure \
  --prefix=. \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-threads \
  --with-pcre=../pcre2-10.47 \
  --with-zlib=../zlib-1.3.1 \
  --with-openssl=../openssl-3.6.0 \
  --with-openssl-opt="no-shared no-module no-secure-memory no-afalgeng CC=musl-gcc AR=ar RANLIB=ranlib CFLAGS='-DOPENSSL_NO_AFALGENG -mno-outline-atomics'" \
  --with-cc-opt='-O2 -pipe -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -D_LARGEFILE64_SOURCE -mno-outline-atomics' \
  --with-ld-opt='-static -Wl,--no-as-needed -latomic'

# Wichtig: -j1, damit OpenSSL erst gebaut wird, bevor gelinkt wird.
make -j1

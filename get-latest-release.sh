#! /usr/bin/env nix-shell
#! nix-shell -i bash -p curl gnused
c=.cache-grapheneos-releases-html
if [ -e "$c" ] ; then
  c2="-z $c"
else
  c2=""
fi
if ! curl https://grapheneos.org/releases $c2 -o $c --silent -L ; then
  echo "Couldn't dowmload GrapheneOS release page!" >&2
  exit 1
fi
x="$(sed -n 's_.*<a href=https://releases[.]grapheneos[.]org/bluejay-factory-\([-a-z0-9A-Z_]*\)[.]zip>.*_\1_p' <$c)"
if [[ "$x" == +([-0-9a-zA-Z_]) ]] ; then
  echo "$x"
else
  echo "Couldn't find bluejay release in release page!" >&2
  exit 1
fi

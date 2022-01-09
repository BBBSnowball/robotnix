#! /usr/bin/env bash
set -euo pipefail

if [[ "$#" -le 0 || ! -e "$1" ]]; then
  echo "Usage: newpassword="..." $0 dir|key..."
  echo "Required tools: openssl"
  echo "  or use: nix-shell default.nix -A generateKeysShell --arg configuration ..."
  echo "If you want to enter the password while someone may be watching, you can use:"
  echo '  newpassword="$(python -c "import getpass; print(getpass.getpass())")"'
  exit 1
fi

for tool in openssl ; do
  if ! which $tool &>/dev/null ; then
    echo "Missing tool: $tool" >&2
    echo "Required tools: openssl"
    exit 1
  fi
done

if [[ -z "${newpassword+x}" ]] ; then
  echo "Set \$newpassword before calling this script, i.e. use: newpassword="..." $0 keys..."
  exit 1
elif [[ -n "${newpassword}" ]] ; then
  echo "Using password from \$newpassword."
else
  echo "Using empty password."
  echo "WARN: This will not work with sign_target_files_apks!"
fi

IFS=$'\n'

change_pw() {
  for key in "$@" ; do
    if [[ -d "$key" ]] ; then
      change_pw $(find "$key" -type f \( -name "*.pk8" -or -name avb.pem -or -name "*.avbpubkey" \) -print)
    elif [[ -f "$key" ]] ; then
      case "/$key" in
        *.pk8)
          change_pw_pk8 "$key"
          ;;
        */avb.pem)
          change_pw_avb "$key"
          ;;
        *.x509.pem)
          echo "Ignoring public key: $key"
          ;;
        *.avbpubkey)
          change_pw_apex "${key%.avbpubkey}.pem"
          ;;
        *.pem)
          # Probably an APEX key since it is not named avb.pem.
          change_pw_apex "$key"
          ;;
        *)
          echo "WARN: Unrecognized file: $key"
          ;;
      esac
    else
      echo "WARN: Ignoring missing or special file: $key"
    fi
  done
}

change_pw_pk8() {
  #NOTE This is using similar openssl commands as the make_key script.
  if openssl pkcs8 -in "$key" -inform DER -nocrypt &>/dev/null ; then
    # saved without password
    # -> nocrypt seems to be required when testing here but it would affect the output when changing the password so omit it there.
    # -> We do need it for the two-step process (see below), which seems to be more robust.
    inargs=( -inform DER -nocrypt )
    #inargs=( -inform DER )
  elif [[ -n "${oldpassword-}" ]] && oldpassword="${oldpassword-}" openssl pkcs8 -in "$key" -inform DER -passin env:oldpassword &>/dev/null ; then
    inargs=( -inform DER -passin env:oldpassword )
  else
    while true ; do
      read -p "Enter current password for '$key' (password will be visible): " oldpassword
      if oldpassword="$oldpassword" openssl pkcs8 -in "$key" -inform DER -passin env:oldpassword >/dev/null ; then
        break
      else
        echo "Wrong password?"
      fi
    done
    inargs=( -inform DER -passin env:oldpassword )
  fi

  if [[ -z "$newpassword" ]] ; then
    outargs=( -nocrypt )
    inargs2=( -nocrypt )
  else
    # make_key uses -scrypt but javax.crypto.EncryptedPrivateKeyInfo wants PBKDF2.
    # -> It still fails with `NoSuchAlgorithmException: 1.2.840.113549.1.5.13' -> "Password-Based Encryption Scheme 2 (PBES2)"
    # -> https://github.com/pgjdbc/pgjdbc/issues/1585#issuecomment-545116845
    # -> SHA1 and triple DES seems to be the best we can do: https://www.openssl.org/docs/manmaster/man1/openssl-pkcs8.html#PKCS-5-V1.5-AND-PKCS-12-ALGORITHMS
    # (view key files with: openssl asn1parse -inform der -i -in keys/redfin/releasekey.pk8)
    #TODO openjdk-11.0.12+7 does support the scrypt keys but the Java that is used in the release script apperently not. Check with master and either switch to scrypt or change the generate script, as well.
    #outargs=( -passout env:newpassword -scrypt )
    outargs=( -passout env:newpassword -v1 PBE-SHA1-3DES )
    inargs2=( -passin  env:newpassword )
  fi

  # change password, read changed key, overwrite original if all is well
  echo "Processing $key"
  if false ; then
    #NOTE make_key passes -topk8 to openssl but we don't need this because the key is already in pk8 format.
    # -> Actually, this doesn't work if the input file already has a password.
    oldpassword="${oldpassword-}" newpassword="$newpassword" \
      openssl pkcs8 -in "$key" "${inargs[@]}" -outform DER -out "$key.tmp" "${outargs[@]}" \
      && newpassword="$newpassword" openssl pkcs8 -in "$key.tmp" -inform DER "${inargs2[@]}" >/dev/null \
      && mv "$key.tmp" "$key" \
      || ( echo "Couldn't change password of $key"; exit 1 )
  else
    # Convert in two steps because the simple way (see above) doesn't work in some cases.
    oldpassword="${oldpassword-}" newpassword="$newpassword" \
      openssl pkcs8 -in "$key" "${inargs[@]}" -outform DER -traditional | openssl pkcs8 -inform DER -outform DER -topk8 -out "$key.tmp" "${outargs[@]}" \
      && newpassword="$newpassword" openssl pkcs8 -in "$key.tmp" -inform DER "${inargs2[@]}" >/dev/null \
      && mv "$key.tmp" "$key" \
      || ( echo "Couldn't change password of $key"; exit 1 )
  fi
}

change_pw_rsa() {
  #TODO which encryption do the relevant tools support, e.g. AES256?
  #     openssl rsa -aes256 -in server.key -out newserver.key
  echo "NOTE Not changing $1 because this script doesn't support this, yet."
}

change_pw_avb() {
  change_pw_rsa "$@"
}

change_pw_apex() {
  change_pw_rsa "$@"
}

change_pw "$@"


Buraya `mfaos.pub` gelecek — cosign ortak anahtarin.

    cosign generate-key-pair
    cp cosign.pub files/etc/pki/containers/mfaos.pub

`cosign.key` ASLA depoya girmemeli. O anahtar, makinelerinin
kabul edecegi her seyi uretebilir; GitHub'da COSIGN_PRIVATE_KEY
secret'i olarak dursun.

Bu dosya olmadan policy.json imzayi dogrulayamaz ve `bootc upgrade`
imaji reddeder.

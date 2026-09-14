# Public, fake-only age identities

Both identities in this directory are deliberately public test fixtures.
Never encrypt real secrets to either recipient or install these as runtime keys.
Tests copy them into private disposable directories and use fake values only.
The second pair exercises wrong-key and wrong-recipient rejection.

Generated with age-keygen 1.3.2:

```sh
age-keygen -o identity.txt
age-keygen -y identity.txt > recipient.txt
age-keygen -o other-identity.txt
age-keygen -y other-identity.txt > other-recipient.txt
```

The age CLI is only a fixture-generation tool. Tests and the provider use SOPS's
built-in age support; neither needs an age executable at runtime.

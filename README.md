# Mojaloop in UAT Env

To deploy Mojaloop to the Mowali UAT Env issue a `git tag` containing the version of the [Helm Chart]() you wish to deploy, followed by a unique ID. It is recommended that the ID be the current date and time. For example:

```bash
git tag v1.2.3-$(date -u "+%Y%m%d%H%M")
git push --tags
```

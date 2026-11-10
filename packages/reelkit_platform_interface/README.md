# reelkit_platform_interface

Common platform interface for ReelKit engines. Applications should depend on
`reelkit`. Engine implementations extend `ReelKitPlatform` and register
themselves with `ReelKitPlatform.instance`.

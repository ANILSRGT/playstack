# playstack_platform_interface

Common platform interface for PlayStack engines. Applications should depend on
`playstack`. Engine implementations extend `PlayStackPlatform` and register
themselves with `PlayStackPlatform.instance`.

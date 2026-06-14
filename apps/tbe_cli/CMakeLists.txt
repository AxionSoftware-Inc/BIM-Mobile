add_executable(tbe_cli
    main.cpp
)

target_link_libraries(tbe_cli PRIVATE tbe_core)
target_link_libraries(tbe_cli PRIVATE tbe_api)

add_executable(api_smoke_demo
    api_smoke_demo.cpp
)

target_link_libraries(api_smoke_demo PRIVATE tbe_api)

add_executable(tbe_apply_command
    tbe_apply_command.cpp
)

target_link_libraries(tbe_apply_command PRIVATE tbe_api)

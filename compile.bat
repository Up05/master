@echo off
cls
chcp 65001
odin run . -use-separate-modules -o:speed -lld -subsystem:windows

cmake_minimum_required(VERSION 3.16)
project(plasma-applet-display-config-switcher)

set(KF_MIN_VERSION "6.0.0")
set(QT_MIN_VERSION "6.6.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

find_package(Plasma REQUIRED)

plasma_install_package(package dev.markusrenken.displayconfigswitcher)

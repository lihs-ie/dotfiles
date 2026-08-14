# Apple Public UI/UX Evidence Profiles

## Visual Theme & Atmosphere

Content-firstで静かな階層を作る。OS固有のsystem renderingを尊重し、Apple純正アプリの見た目や非公開componentを複製しない。

## Color Palette & Roles

system/semantic colorを役割で指定する。固定RGBはbrand asset、illustration、data visualizationなど正当化された用途だけに限定し、Light/Dark、Increase Contrast、Differentiate Without Colorで検証する。

## Typography Rules

SwiftUIのsemantic text styleまたはUIKitのpreferred text styleを使う。固定font sizeを規範化しない。標準とaccessibility最大を含むDynamic Typeでreflow、clipping、truncationを確認する。

## Component Stylings

NavigationStack、NavigationSplitView、TabView、UINavigationController、UISplitViewController、system Button、List、Form、Menu、Sheet、Alertなどのdocumented componentを優先する。custom componentはsystem equivalentがなく、例外記録がある場合だけ使う。

## Layout Principles

semantic container、safe area、readable content、adaptive layoutを優先する。公開根拠のない万能spacing gridやcorner radiusを発明しない。iPadの幅変更でdomain dataとrecoverable navigation stateを失わない。

## Depth & Elevation

OS 18 profileとOS 26 Liquid Glass profileを混ぜない。Liquid Glassはnavigation/control layerを中心にsystem componentへ委ね、glass-on-glassや装飾目的の過剰利用を避ける。

## Do's and Don'ts

Do: semantic API、system behavior、accessible alternative、predictable state transition、evidence-backed exception。

Don't: pixel copy、固定値によるApple風表現、color/motion/gestureだけに依存する意味伝達、未確認の適合宣言。

## Responsive Behavior

iPhoneとiPad、compact/intermediate/regular width、portrait/landscape、ja-JP/en-US、Light/Dark、Dynamic Typeを扱う。pointer、keyboard、Pencilはtouchを置き換えず追加経路として設計する。

## Agent Prompt Guide

画面の意味、主要task、状態、navigation、input mode、accessibility、profileを先に確定する。重複しない3方向を作り、1案選択後に重要状態を展開する。明示承認前にnative実装へ進まない。

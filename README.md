# sh_terminator

Нативный терминал для macOS с разделением окна на панели (как в iTerm2/tmux),
спроектированный так, чтобы в нём безопасно держать на экране пароли, ключи
и seed-фразы. Полный разбор того, что и как защищено — в [SECURITY.md](SECURITY.md).

## Сборка и запуск

Нужны только Xcode Command Line Tools (полноценный Xcode.app не требуется).

```sh
./Scripts/build-app.sh      # swift build -c release + упаковка в .app + codesign
open dist/SHTerminator.app
```

Для разработки без пересборки `.app`:
```sh
swift run
```

## Горячие клавиши

| Действие                         | Клавиши   |
|-----------------------------------|-----------|
| Новое окно                       | ⌘N        |
| Новое окно из шаблона            | File → New Window From Template → 2/4/6/8/10 панелей |
| Разделить вертикально (слева/справа) | ⌘D    |
| Разделить горизонтально (сверху/снизу) | ⌘⇧D |
| Закрыть панель                   | ⌘W        |
| Закрыть всё окно                 | ⌘⇧W       |
| Следующая / предыдущая панель    | ⌘] / ⌘[   |
| Развернуть панель на всё окно    | ⌘↩ (toggle) |
| Copy & Clear Clipboard после 20с | ⌥⌘C       |

Клик по панели тоже переключает на неё фокус.

## Структура проекта

```
Sources/SHTerminator/
  main.swift                  — запуск NSApplication
  AppDelegate.swift           — меню, список открытых окон
  PTY/PaneSession.swift       — один шелл-процесс на отдельном pty = одна панель
  Layout/PaneNode.swift       — дерево раскладки (как в tmux/iTerm2)
  Layout/SplitPaneController.swift — дерево → живая иерархия NSSplitView
  Layout/PaneTemplates.swift  — готовые раскладки 2/4/6/8/10 панелей
  UI/                         — окно, меню, equal-split NSSplitView
  Security/SecurityHardening.swift — весь чек-лист защиты в одном месте
```

Единственная внешняя зависимость — [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm),
запинена точной версией в `Package.swift`/`Package.resolved`. Подробности и
обоснование — в SECURITY.md.

## Вне текущего скоупа

Preferences UI (шрифт/тема/шелл по умолчанию), вкладки, сохранение и
восстановление *раскладки* окна (без содержимого панелей), экспорт лога
сессии по явному запросу пользователя. Не реализовано — делается только по
отдельной просьбе.

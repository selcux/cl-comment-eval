# cl-comment-eval

Evaluate forms inside `(comment ...)` blocks in Common Lisp buffers, with inline result display — similar to [Calva's Rich Comment](https://calva.io/rich-comments/) feature for Clojure.

Works with both **SLY** and **SLIME**.

## What is this?

In Common Lisp it's common to define a `comment` macro that discards its body:

```lisp
(defmacro comment (&rest _body) nil)
```

This lets you keep scratch expressions alongside your code — a lightweight scratchpad that won't be executed on load. `cl-comment-eval` lets you evaluate those expressions individually, with results shown inline next to each form.

```lisp
(comment
  (+ 1 2)      ; => 3
  (* 6 7)      ; => 42
  (list 1 2 3) ; => (1 2 3)
)
```

[Serapeum](https://github.com/ruricolist/serapeum) ships a `comment` macro out of the box — `serapeum:comment` is recognized automatically.

## Requirements

- Emacs 27.1+
- [SLY](https://github.com/joaotavora/sly) or [SLIME](https://slime.common-lisp.dev/)

## Installation

### Doom Emacs

Add to `packages.el`:

```elisp
(package! cl-comment-eval
  :recipe (:local-repo "/path/to/cl-comment-eval"))
```

Add to `config.el`:

```elisp
(use-package! cl-comment-eval
  :hook (lisp-mode . cl-comment-eval-mode))
```

Then run `doom sync`.

### straight.el

```elisp
(straight-use-package
  '(cl-comment-eval :local-repo "/path/to/cl-comment-eval"))

(add-hook 'lisp-mode-hook #'cl-comment-eval-mode)
```

### Manual

Clone or copy `cl-comment-eval.el` somewhere on your `load-path`, then:

```elisp
(require 'cl-comment-eval)
(add-hook 'lisp-mode-hook #'cl-comment-eval-mode)
```

## Usage

Enable `cl-comment-eval-mode` in any Common Lisp buffer (or let the hook do it automatically). The mode indicator ` CE` appears in the mode line when active.

### Keybinding

| Key | Behaviour |
|-----|-----------|
| `C-c C-j` | **Inside a form** — evaluate that form and show result inline. **Between forms or on the `(comment` line** — evaluate all child forms in the block. |
| `M-x cl-comment-eval-clear-overlays` | Remove all result overlays from the buffer. |

Results appear inline as italic green text after each evaluated form:

```
(comment
  (+ 1 2)  => 3
  (* 6 7)  => 42
)
```

- Each form's result is independent — re-evaluating one form updates only its overlay.
- Overlays disappear automatically when you edit the buffer.

## Package-qualified comment symbols

Any package-qualified form of a configured symbol is recognized automatically. If your project uses `serapeum:comment` or `mylib::comment`, no extra configuration is needed — both are matched by the default `"comment"` entry.

To add support for a custom comment macro named `scratch`:

```elisp
(setq cl-comment-eval-comment-symbols '("comment" "scratch"))
```

## Customization

All options are in the `cl-comment-eval` customize group (`M-x customize-group RET cl-comment-eval`).

| Variable | Default | Description |
|----------|---------|-------------|
| `cl-comment-eval-comment-symbols` | `'("comment")` | Bare symbol names treated as comment blocks. Package-qualified variants are matched automatically. |
| `cl-comment-eval-backend` | `'auto` | Evaluation backend: `auto` (prefer connected session), `sly`, or `slime`. |
| `cl-comment-eval-show-overlay` | `t` | Show results as inline overlays. Set to `nil` to display in the minibuffer instead. |
| `cl-comment-eval-overlay-max-length` | `80` | Truncate inline results longer than this many characters. |

### Faces

| Face | Description |
|------|-------------|
| `cl-comment-eval-result-face` | The result value text. Defaults to italic green (dark/light theme aware). |
| `cl-comment-eval-result-delimiter-face` | The ` => ` separator. Defaults to bold shadow. |

Customize with `M-x customize-face` or in your theme:

```elisp
(custom-set-faces
  '(cl-comment-eval-result-face
    ((t :foreground "#c792ea" :slant italic))))
```

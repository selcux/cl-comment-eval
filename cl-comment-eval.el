;;; cl-comment-eval.el --- Evaluate forms inside (comment ...) blocks  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author:
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: lisp, tools
;; URL:

;;; Commentary:

;; Evaluate individual forms inside (comment ...) blocks in Common Lisp
;; buffers, similar to Calva's behaviour in Clojure.  Works with both
;; SLY and SLIME — whichever is active in the current buffer.
;;
;; Usage:
;;   M-x cl-comment-eval-mode   (or add to lisp-mode-hook)
;;   Place point on a form inside (comment ...), press C-c C-e.

;;; Code:

;;;; Customization

(defgroup cl-comment-eval nil
  "Evaluate forms inside Common Lisp comment blocks."
  :group 'lisp)

(defcustom cl-comment-eval-comment-symbols '("comment")
  "Bare symbol names (without package prefix) treated as comment blocks.
Package-qualified forms are also recognized automatically, so adding
\"comment\" here matches `comment', `serapeum:comment', `mylib::comment', etc."
  :type '(repeat string)
  :group 'cl-comment-eval)

(defcustom cl-comment-eval-backend 'auto
  "Backend to use for evaluation.
`auto' detects from connected sessions; `sly' or `slime' force a specific
backend regardless of connection state."
  :type '(choice (const :tag "Auto-detect" auto)
                 (const :tag "SLY" sly)
                 (const :tag "SLIME" slime))
  :group 'cl-comment-eval)

;;;; Navigation — pure buffer-position functions

(defun cl-comment-eval--comment-regexp ()
  "Return a regexp matching any configured comment-block symbol, with or without package prefix."
  (concat "(\\(?:[^[:space:]]*:\\)?\\(?:"
          (mapconcat #'regexp-quote cl-comment-eval-comment-symbols "\\|")
          "\\)\\_>"))

(defun cl-comment-eval--enclosing-comment-pos ()
  "Return position of `(' of nearest enclosing (comment ...) form, or nil."
  (save-excursion
    (catch 'found
      (condition-case nil
          (while t
            ;; escape-strings=t so we can navigate up from inside string literals
            (backward-up-list 1 t)
            (when (looking-at (cl-comment-eval--comment-regexp))
              (throw 'found (point))))
        (scan-error nil)))))

(defun cl-comment-eval--form-bounds ()
  "Return (START . END) of the direct child sexp of (comment ...) at point.
Returns nil if point is not inside a (comment ...) block or is on whitespace
between forms."
  (let ((pt (point)))
    (when-let ((comment-pos (cl-comment-eval--enclosing-comment-pos)))
      (save-excursion
        (goto-char comment-pos)
        (down-list)       ; enter past `('
        (forward-sexp)    ; skip the `comment' symbol
        (catch 'found
          (condition-case nil
              (while t
                (skip-chars-forward " \t\n\r")
                (let ((start (point)))
                  (forward-sexp)
                  (when (and (<= start pt) (<= pt (point)))
                    (throw 'found (cons start (point))))))
            (scan-error nil)))))))

;;;; Backend detection and dispatch

(defun cl-comment-eval--active-backend ()
  "Return `sly', `slime', or nil depending on what is available.
Respects `cl-comment-eval-backend' when non-auto.  When auto, prefers a
connected session; falls back to whichever backend is loaded."
  (cond
   ((eq cl-comment-eval-backend 'sly)   'sly)
   ((eq cl-comment-eval-backend 'slime) 'slime)
   ((and (featurep 'sly)
         (fboundp 'sly-connected-p)
         (sly-connected-p))
    'sly)
   ((and (featurep 'slime)
         (fboundp 'slime-connected-p)
         (slime-connected-p))
    'slime)
   ((featurep 'sly)   'sly)
   ((featurep 'slime) 'slime)
   (t nil)))

(defun cl-comment-eval--eval-string (string)
  "Evaluate STRING via the active CL backend."
  (pcase (cl-comment-eval--active-backend)
    ('sly   (sly-interactive-eval string))
    ('slime (slime-interactive-eval string))
    (_      (user-error "cl-comment-eval: no CL backend available (install SLY or SLIME)"))))

;;;; User-facing command and minor mode

;;;###autoload
(defun cl-comment-eval ()
  "Evaluate the direct child sexp of the enclosing (comment ...) block.
Dispatches to SLY or SLIME depending on which is active."
  (interactive)
  (let ((bounds (cl-comment-eval--form-bounds)))
    (unless bounds
      (user-error "Point is not inside a (comment ...) block"))
    (cl-comment-eval--eval-string
     (buffer-substring-no-properties (car bounds) (cdr bounds)))))

;;;###autoload
(define-minor-mode cl-comment-eval-mode
  "Minor mode for evaluating forms inside (comment ...) blocks.
\\{cl-comment-eval-mode-map}"
  :lighter " CE"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-j") #'cl-comment-eval)
            map))

(provide 'cl-comment-eval)
;;; cl-comment-eval.el ends here

;;; cl-comment-eval.el --- Evaluate forms inside (comment ...) blocks  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author:
;; Version: 0.2.0
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
;;   C-c C-j  — eval form at point; if between forms, eval all in block
;;   M-x cl-comment-eval-clear-overlays  — clear result overlays manually

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

(defcustom cl-comment-eval-show-overlay t
  "When non-nil, show evaluation results as inline overlays."
  :type 'boolean
  :group 'cl-comment-eval)

(defcustom cl-comment-eval-overlay-max-length 80
  "Maximum character length of an inline result. Longer values are truncated."
  :type 'integer
  :group 'cl-comment-eval)

;;;; Face

(defface cl-comment-eval-result-delimiter-face
  '((t :inherit shadow :weight bold))
  "Face for the ` => ' separator in result overlays."
  :group 'cl-comment-eval)

(defface cl-comment-eval-result-face
  '((((background dark))  :foreground "#a8d8a8" :slant italic)
    (((background light)) :foreground "#2a7a2a" :slant italic)
    (t                    :inherit shadow       :slant italic))
  "Face for inline evaluation result text."
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

(defun cl-comment-eval--all-child-bounds ()
  "Return a list of (START . END) for every direct child of the enclosing comment block."
  (when-let ((comment-pos (cl-comment-eval--enclosing-comment-pos)))
    (save-excursion
      (goto-char comment-pos)
      (down-list)
      (forward-sexp)   ; skip `comment' symbol
      (let (result)
        (condition-case nil
            (while t
              (skip-chars-forward " \t\n\r")
              (let ((start (point)))
                (forward-sexp)
                (push (cons start (point)) result)))
          (scan-error nil))
        (nreverse result)))))

;;;; Overlay display

(defvar-local cl-comment-eval--overlays nil
  "List of active result overlays in this buffer.")

(defun cl-comment-eval--clear-overlay-at (pos)
  "Remove any existing result overlay at POS."
  (setq cl-comment-eval--overlays
        (cl-remove-if (lambda (ov)
                        (when (= (overlay-start ov) pos)
                          (delete-overlay ov)
                          t))
                      cl-comment-eval--overlays)))

(defun cl-comment-eval--show-overlay (pos value)
  "Display VALUE as an overlay after POS."
  (cl-comment-eval--clear-overlay-at pos)
  (let* ((text (if (> (length value) cl-comment-eval-overlay-max-length)
                   (concat (substring value 0 cl-comment-eval-overlay-max-length) "…")
                 value))
         (ov (make-overlay pos pos)))
    (overlay-put ov 'after-string
                 (concat
                  (propertize " => " 'face 'cl-comment-eval-result-delimiter-face)
                  (propertize text   'face 'cl-comment-eval-result-face)))
    (overlay-put ov 'cl-comment-eval t)
    (push ov cl-comment-eval--overlays)))

(defun cl-comment-eval-clear-overlays ()
  "Remove all result overlays from the current buffer."
  (interactive)
  (mapc #'delete-overlay cl-comment-eval--overlays)
  (setq cl-comment-eval--overlays nil))

(defun cl-comment-eval--clear-on-change (&rest _)
  (when cl-comment-eval--overlays
    (cl-comment-eval-clear-overlays)))

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
  "Evaluate STRING via the active CL backend (minibuffer result display)."
  (pcase (cl-comment-eval--active-backend)
    ('sly   (sly-interactive-eval string))
    ('slime (slime-interactive-eval string))
    (_      (user-error "cl-comment-eval: no CL backend available (install SLY or SLIME)"))))

(defun cl-comment-eval--eval-async (string end-pos)
  "Evaluate STRING and show result as overlay after END-POS."
  (let ((buf (current-buffer))
        (pos end-pos))
    (pcase (cl-comment-eval--active-backend)
      ('sly
       (sly-eval-async `(slynk:eval-and-grab-output ,string)
         (lambda (result)
           (with-current-buffer buf
             (cl-comment-eval--show-overlay pos (cadr result))))
         (sly-current-package)))
      ('slime
       (slime-eval-async `(swank:eval-and-grab-output ,string)
         (lambda (result)
           (with-current-buffer buf
             (cl-comment-eval--show-overlay pos (cadr result))))
         (slime-current-package)))
      (_ (user-error "cl-comment-eval: no CL backend available (install SLY or SLIME)")))))

(defun cl-comment-eval--eval-one (bounds)
  "Evaluate the form described by BOUNDS, using overlay or minibuffer as configured."
  (let ((str (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (if cl-comment-eval-show-overlay
        (cl-comment-eval--eval-async str (cdr bounds))
      (cl-comment-eval--eval-string str))))

;;;; User-facing command and minor mode

;;;###autoload
(defun cl-comment-eval ()
  "Evaluate form at point inside a (comment ...) block.
If point is inside a specific child form, evaluate that form.
If point is between forms or on the (comment ...) line, evaluate all children."
  (interactive)
  (let ((bounds (cl-comment-eval--form-bounds)))
    (cond
     (bounds
      (cl-comment-eval--eval-one bounds))
     ((cl-comment-eval--enclosing-comment-pos)
      (let ((all (cl-comment-eval--all-child-bounds)))
        (dolist (b all)
          (cl-comment-eval--eval-one b))))
     (t
      (user-error "Point is not inside a (comment ...) block")))))

;;;###autoload
(define-minor-mode cl-comment-eval-mode
  "Minor mode for evaluating forms inside (comment ...) blocks.
\\{cl-comment-eval-mode-map}"
  :lighter " CE"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-j") #'cl-comment-eval)
            map)
  (if cl-comment-eval-mode
      (add-hook 'before-change-functions #'cl-comment-eval--clear-on-change nil t)
    (remove-hook 'before-change-functions #'cl-comment-eval--clear-on-change t)
    (cl-comment-eval-clear-overlays)))

(provide 'cl-comment-eval)
;;; cl-comment-eval.el ends here

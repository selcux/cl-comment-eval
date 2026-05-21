;;; cl-comment-eval-tests.el --- ERT tests for cl-comment-eval  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run interactively: M-x ert RET t RET
;; Run from shell:
;;   emacs -batch -l cl-comment-eval.el -l cl-comment-eval-tests.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-comment-eval)

;;;; Helper

(defmacro with-cl-buffer (content &rest body)
  "Run BODY in a temp `lisp-mode' buffer containing CONTENT.
The string |HERE| in CONTENT marks where point is placed (and is removed)."
  (declare (indent 1))
  `(with-temp-buffer
     (lisp-mode)
     (insert ,content)
     (goto-char (point-min))
     (when (search-forward "|HERE|" nil t)
       (replace-match ""))
     ,@body))

;;;; cl-comment-eval--enclosing-comment-pos

(ert-deftest cce-enclosing-comment-pos/inside-comment ()
  (with-cl-buffer "(comment\n  (+ 1 |HERE|2))"
    (let ((pos (cl-comment-eval--enclosing-comment-pos)))
      (should pos)
      (save-excursion
        (goto-char pos)
        (should (looking-at "(comment\\_>"))))))

(ert-deftest cce-enclosing-comment-pos/not-in-comment ()
  (with-cl-buffer "(defun foo ()\n  (+ 1 |HERE|2))"
    (should-not (cl-comment-eval--enclosing-comment-pos))))

(ert-deftest cce-enclosing-comment-pos/at-top-level ()
  (with-cl-buffer "|HERE|(foo)"
    (should-not (cl-comment-eval--enclosing-comment-pos))))

(ert-deftest cce-enclosing-comment-pos/nested-in-let ()
  (with-cl-buffer "(let ((x 1))\n  (comment\n    (+ x |HERE|2)))"
    (let ((pos (cl-comment-eval--enclosing-comment-pos)))
      (should pos)
      (save-excursion
        (goto-char pos)
        (should (looking-at "(comment\\_>"))))))

(ert-deftest cce-enclosing-comment-pos/package-qualified ()
  "`(serapeum:comment ...)' is recognized."
  (with-cl-buffer "(serapeum:comment\n  (+ 1 |HERE|2))"
    (should (cl-comment-eval--enclosing-comment-pos))))

(ert-deftest cce-enclosing-comment-pos/double-colon ()
  "`(pkg::comment ...)' is recognized."
  (with-cl-buffer "(pkg::comment\n  (+ 1 |HERE|2))"
    (should (cl-comment-eval--enclosing-comment-pos))))

(ert-deftest cce-enclosing-comment-pos/word-boundary ()
  "`(comment-foo ...)' must NOT be treated as a comment block."
  (with-cl-buffer "(comment-foo\n  (+ 1 |HERE|2))"
    (should-not (cl-comment-eval--enclosing-comment-pos))))

;;;; cl-comment-eval--form-bounds helpers

(defun cce--extract (content)
  "Return the extracted sexp string for cursor position in CONTENT."
  (with-cl-buffer content
    (when-let ((bounds (cl-comment-eval--form-bounds)))
      (buffer-substring-no-properties (car bounds) (cdr bounds)))))

;;;; cl-comment-eval--form-bounds

(ert-deftest cce-form-bounds/simple-sexp ()
  (should (equal "(+ 1 2)"
                 (cce--extract "(comment\n  (+ 1 |HERE|2))"))))

(ert-deftest cce-form-bounds/multiple-children-first ()
  (should (equal "(+ 1 2)"
                 (cce--extract "(comment\n  (+ 1 |HERE|2)\n  (- 3 4))"))))

(ert-deftest cce-form-bounds/multiple-children-second ()
  (should (equal "(- 3 4)"
                 (cce--extract "(comment\n  (+ 1 2)\n  (- 3 |HERE|4))"))))

(ert-deftest cce-form-bounds/point-on-opening-paren ()
  (should (equal "(+ 1 2)"
                 (cce--extract "(comment\n  |HERE|(+ 1 2))"))))

(ert-deftest cce-form-bounds/point-on-closing-paren ()
  (should (equal "(+ 1 2)"
                 (cce--extract "(comment\n  (+ 1 2|HERE|))"))))

(ert-deftest cce-form-bounds/atom-child ()
  "A bare symbol as a direct child of the comment block."
  (should (equal "foo"
                 (cce--extract "(comment\n  fo|HERE|o)"))))

(ert-deftest cce-form-bounds/not-in-comment ()
  (should-not (cce--extract "(defun foo ()\n  (+ 1 |HERE|2))")))

(ert-deftest cce-form-bounds/between-forms-whitespace ()
  "Point on blank line between two child forms returns nil."
  (should-not (cce--extract "(comment\n  (+ 1 2)\n|HERE|\n  (- 3 4))")))

(ert-deftest cce-form-bounds/string-child ()
  (should (equal "\"hello world\""
                 (cce--extract "(comment\n  \"hello |HERE|world\")"))))

(ert-deftest cce-form-bounds/deeply-nested-point ()
  "Point deep inside a nested child returns the top-level child."
  (should (equal "(let ((x (+ 1 2))) x)"
                 (cce--extract
                  "(comment\n  (let ((x (+ 1 |HERE|2))) x))"))))

;;;; cl-comment-eval--all-child-bounds

(ert-deftest cce-all-child-bounds/two-children ()
  (with-cl-buffer "(comment\n  (+ 1 2)\n  |HERE|(- 3 4))"
    (let ((bounds (cl-comment-eval--all-child-bounds)))
      (should (= 2 (length bounds)))
      (should (equal "(+ 1 2)" (buffer-substring-no-properties
                                (car (nth 0 bounds)) (cdr (nth 0 bounds)))))
      (should (equal "(- 3 4)" (buffer-substring-no-properties
                                (car (nth 1 bounds)) (cdr (nth 1 bounds))))))))

(ert-deftest cce-all-child-bounds/not-in-comment ()
  (with-cl-buffer "(defun foo ()\n  |HERE|(+ 1 2))"
    (should-not (cl-comment-eval--all-child-bounds))))

(ert-deftest cce-all-child-bounds/single-atom ()
  (with-cl-buffer "(comment\n  |HERE|42)"
    (let ((bounds (cl-comment-eval--all-child-bounds)))
      (should (= 1 (length bounds)))
      (should (equal "42" (buffer-substring-no-properties
                           (caar bounds) (cdar bounds)))))))

(provide 'cl-comment-eval-tests)
;;; cl-comment-eval-tests.el ends here

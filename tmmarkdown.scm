;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MODULE      : tmmarkdown.scm
;; DESCRIPTION : TeXmacs-stree to markdown-stree converter
;; COPYRIGHT   : (C) 2017 Ana Cañizares García and Miguel de Benito Delgado
;;
;; This software falls under the GNU general public license version 3 or later.
;; It comes WITHOUT ANY WARRANTY WHATSOEVER. For details, see the file LICENSE
;; in the root directory or <http://www.gnu.org/licenses/gpl-3.0.html>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(texmacs-module (convert markdown tmmarkdown)
  (:use (convert markdown markdownout)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Helper functions for the transformation of strees and dispatcher
;; TODO: use TeXmacs' logic-dispatch, export sessions, bibliography
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; For some reason we always receive an stree, so we cannot use tm-file?
; because it expects its argument to be a tree and at some point queries a
; string for its tree-label and obviously fails... duh.
(define (is-file? x)
  (and (func? x 'document)
       (== 1 (length (select x '(body))))))

(define (keep x)
  "Recursively processes @x while leaving its func untouched."
  (cons (car x) (map texmacs->markdown* (cdr x))))

(define (change-to func)
  ; (a . b) -> (func . b)
  (lambda (x)
    (cons func (map texmacs->markdown* (cdr x)))))

(define (hrule-hack x)
  ; FIXME: this breaks inside quotations and whatnot. And it's ugly.
  '(document "" "---" ""))

(define (skip x)
  "Recursively processes @x and drops its func."
  (display* "Skipped " (car x) "\n")
  (map texmacs->markdown* (cdr x)))

(define (drop x)
  (display* "Dropped " (car x) " !\n")
  '())

(define (url-temp-ext ext)
  (url-glue (url-temp) (string-append "." ext)))

(define (texmacs->png x)
  (let ((tmp-pdf (url-temp-ext "pdf")) (tmp-png (url-temp-ext "png")))
  (begin
    (print-snippet tmp-png x #t)
    ;(file-convert tmp-pdf tmp-png)
    (url-concretize tmp-png)
    )
    )
  )

(define (md-image x)
  (list 'figure (texmacs->png x) "")
  )

(define (parse-big-figure x)
  ; Example input:
  ; (big-figure (image "path-to.jpeg" "251px" "251px" "" "") 
  ;             (document "caption"))
  ; Or, when the "Figure num." in the figure is removed:
  ; (render-big-figure "" "Figure text" (image ...) (document "caption"))
  ;
  ; FIXME: We need to ignore the text until we write a Hugo shortcode
  ; implementing Figure text as TeXmacs.
  (let* ((offset (if (func? x 'big-figure) 0 2))
         (img (tm-ref x offset))
         (caption (texmacs->markdown* (tm-ref x (+ 1 offset))))
         (src (if (tm-is? img 'image) 
                  (texmacs->png x)
                  '(document "Wrong image src"))))
    (list 'figure src caption)))

(define (parse-with x)
  ; HACK: we end up calling ourselves with (with "stuff"), which
  ; actually is a malformed 'with tag but it's handy
  (cond ((== 1 (tm-length x)) (texmacs->markdown* (tm-ref x 0)))
        ((and (== "font-series" (tm-ref x 0))
              (== "bold" (tm-ref x 1)))
         `(strong ,(parse-with (cons 'with (cdddr x)))))
        ((and (== "font-shape" (tm-ref x 0))
              (== "italic" (tm-ref x 1)))
         `(em ,(parse-with (cons 'with (cdddr x)))))
        ((and (== "mode" (tm-ref x 0))
              (== "prog" (tm-ref x 1)))
         `(tt ,(parse-with (cons 'with (cdddr x)))))
        (else (parse-with (cons 'with (cdddr x))))))

; TO-DO
(define (parse-bibliography x)
  ; Input:
  ; (bibliography "bib-name" "bib-type" "bib-file" 
  ;   (doc (bib-list "n" (doc (concat 1...) (concat 2... ) ... (concat n...)))))
  '())

(define (code-block syntax)
  (lambda (x)
    `(block ,syntax ,@(cdr x))))

(define (math->latex t)
 "Converts the TeXmacs tree @t into internal LaTeX representation"
 (with options '(("texmacs->latex:replace-style" . "on")
                 ("texmacs->latex:expand-macros" . "on")
                 ("texmacs->latex:expand-user-macros" . "off")
                 ("texmacs->latex:indirect-bib" . "off")
                 ("texmacs->latex:encoding" . "utf8")
                 ("texmacs->latex:use-macros" . "off"))
 (texmacs->latex t options)))

(define (hack-math x)
  (let*  ((s (serialize-latex (math->latex x)))
          (s1 (string-replace s "\\ensuremath" ""))
         )
         s1))

(define (md-math x)
   (list (hack-math x)))

(define (md-equation x)
  (let*  ((s (hack-math x))
          (s1 (string-replace s "\\[" "$$\n"))
          (s2 (string-replace s1 "\\]" "\n$$"))
         )
          (list s2)
          ; (list "equation")
          ))

(define (md-eqnarray* x)
   (let* ((s (hack-math x))
          (s1 (string-replace s "\\begin{eqnarray*}" "\\begin{array}{rcl}"))
          (s2 (string-replace s1 "\\end{eqnarray*}" "\\end{array}")))
          (list (string-append 
              "$$\n" 
              s2 
              "\n$$"))))
   

(define (md-keep-string x) 
    (cons (symbol->string (car x)) (map texmacs->markdown* (cdr x))))

(define (scheme-input x) 
  (let* ((input-doc (list-ref x 2))
         (input-content (cdr input-doc))
       )
     input-content
   )
)

(define (scheme-output x)
   (cond ((< (length x) 4) "")
         (else 
           (let* ((output-doc (list-ref x 3))
                  
                 )
                 (map (lambda (it)
                              (cond ((string? it) it)
                                    (else "")
                              ))
                       output-doc
            )
           )
         )
   )
  )

(define (md-session x) 
  (let ((language-name (list-ref x 1))
        (session-list (cdr (cadr (cddr x))))
       )
       (map (lambda (single-session) (md-session-sub single-session language-name)) session-list)
  )
)

(define (md-session-sub x language-name) 
  (cond ((== (car x) 'session) (md-session x))
        (else 
           (let* ((session-name (get-session-name (cadr x)))
         (input-content (scheme-input x))
         (output-content (scheme-output x))
        )
    (cons 'session `(" " "```" ,language-name " " 
       ,(language-comment-symbol language-name) ,session-name " "
       ,@(insert-newline-in-list input-content) " "
       "```" " "
       ,@(insert-newline-in-list output-content) " ")))  
        )
    )
  
  )
(define (language-comment-symbol s)
        (cond ((== "scheme" s) ";;; ")
              ((== "python" s) "### ")
              (else "// ")
        ))
(define (get-session-name x)
  (cond ((list? x) (cadr x))
        ((string? x) x)
        (else "")))

(define (insert-newline-in-list x)
  (cond ((nlist>0? x) '())
        (else `(,(car x) " "  ,@(insert-newline-in-list (cdr x))))))  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Dispatch
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define conversion-hash (make-ahash-table))
(map (lambda (l) (apply (cut ahash-set! conversion-hash <> <>) l)) 
     (list (list 'TeXmacs md-keep-string)
           (list 'strong keep)
           (list 'dfn (change-to 'strong))
           (list 'em keep)
           (list 'strike-through (change-to 'strike)) ; non-standard extension
           (list 'hrule hrule-hack)
           (list 'samp (change-to 'tt))
           (list 'python (change-to 'tt))
           (list 'cpp (change-to 'tt))
           (list 'scm (change-to 'tt))
           (list 'mmx (change-to 'tt))
           (list 'scilab (change-to 'tt))
           (list 'shell (change-to 'tt))
           (list 'verbatim (change-to 'tt))
           (list 'verbatim-code (code-block ""))
           (list 'code (code-block ""))
           (list 'scm-code (code-block "scheme"))
           (list 'cpp-code (code-block "c++"))
           (list 'mmx-code (code-block "mmx"))
           (list 'python-code (code-block "python"))
           (list 'scilab-code (code-block "scilab"))
           (list 'shell-code (code-block "shell"))
           (list 'author-name identity)
           (list 'author-email drop)
           (list 'document keep)
           (list 'quotation keep)
           (list 'definition keep)
           (list 'definition* keep)           
           (list 'conjecture keep)
           (list 'conjecture* keep)           
           (list 'question keep)
           (list 'question* keep)           
           (list 'algorithm keep)
           (list 'algorithm* keep)           
           (list 'problem keep)
           (list 'problem* keep)           
           (list 'theorem keep)
           (list 'theorem* keep)           
           (list 'proposition keep)
           (list 'proposition* keep)           
           (list 'corollary keep)
           (list 'corollary* keep)           
           (list 'lemma keep)
           (list 'lemma* keep)           
           (list 'proof keep)
           (list 'proof* keep)                      
           (list 'dueto keep)
           (list 'math md-math)
           (list 'equation md-equation)
           (list 'equation* md-equation)
           (list 'eqnarray* md-eqnarray*)
           (list 'concat keep)
           (list 'doc-title keep)
           (list 'doc-running-author keep)
           (list 'section (change-to 'h2))
           (list 'section* (change-to 'h2))           
           (list 'subsection (change-to 'h3))
           (list 'subsection* (change-to 'h3))
           (list 'subsubsection (change-to 'h4))
           (list 'subsubsection* (change-to 'h4))
           (list 'paragraph (change-to 'strong))
           (list 'subparagraph (change-to 'strong))
           (list 'with parse-with)
           (list 'itemize keep)
           (list 'itemize-minus (change-to 'itemize))
           (list 'itemize-dot (change-to 'itemize))
           (list 'itemize-arrow (change-to 'itemize))
           (list 'enumerate keep)
           (list 'enumerate-roman (change-to 'enumerate))
           (list 'enumerate-Roman (change-to 'enumerate))
           (list 'enumerate-alpha keep)
           (list 'enumerate-Alpha (change-to 'enumerate-alpha))
           (list 'item keep)
           (list 'cite keep)
           (list 'cite-detail keep)
           (list 'hlink keep)
           (list 'eqref keep)
           (list 'label keep)
           (list 'reference keep)
           (list 'big-figure parse-big-figure)
           (list 'small-figure parse-big-figure)
           (list 'image md-image)
           ;(list 'render-big-figure parse-big-figure)
           (list 'footnote keep)
           (list 'bibliography drop)
           (list 'hide-preamble drop)
           (list 'session md-session)
           (list 'tags keep)  ; extension in paperwhy.ts for Hugo tags
           (list 'hugo keep)  ; extension in paperwhy.ts for Hugo shortcodes
           ))

(define (texmacs->markdown* x)
  (cond ((not (list>0? x)) x)
        ((symbol? (car x))
         (with fun (ahash-ref conversion-hash (car x))
           (if (!= fun #f)
               (fun x)
               (skip x))))
        (else (cons (texmacs->markdown* (car x))
                    (texmacs->markdown* (cdr x))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public interface
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(tm-define (texmacs->markdown x)
  (if (is-file? x)
      (texmacs->markdown* (car (select x '(body document))))
      (texmacs->markdown* x)))

(tm-define (tm->md x) (texmacs->markdown x))
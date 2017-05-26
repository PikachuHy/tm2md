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
;; TODO: use TeXmacs' logic-dispatch
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (keep x)
  "Recursively processes @x while leaving its func untouched."
  (cons (car x) (map texmacs->markdown* (cdr x))))

(define (change-to func)
  ; (a . b) -> (func . b)
  (lambda (x)
    (cons func (map texmacs->markdown* (cdr x)))))

(define (skip x)
  "Recursively processes @x and drops its func."
  (map texmacs->markdown* (cdr x)))

(define (drop x)
  '())

(define (parse-big-figure x)
  ; Example input:
  ; (big-figure (image "path-to.jpeg" "251px" "251px" "" "") 
  ;             (document "caption"))
  (let* ((img (tm-ref x 0))
         (caption (texmacs->markdown* (tm-ref x 1)))
         (src (if (tm-is? img 'image) 
                  (tm-ref img 0)
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
        (else (skip x))))

; TO-DO
(define (process-bibliography x)
  ; Input:
  ; (bibliography "bib-name" "bib-type" "bib-file" 
  ;   (doc (bib-list "n" (doc (concat 1...) (concat 2... ) ... (concat n...)))))
  '())

;TODO: session, code blocks, bibliography
(define conversion-hash (make-ahash-table))
(map (lambda (l) (apply (cut ahash-set! conversion-hash <> <>) l)) 
     (list (list 'strong keep)
           (list 'dfn (change-to 'strong))
           (list 'em keep)
           (list 'strike-through (change-to 'strike)) ; non-standard extension
           (list 'samp (change-to 'tt))
           (list 'python (change-to 'tt))
           (list 'cpp (change-to 'tt))
           (list 'scm (change-to 'tt))
           (list 'mmx (change-to 'tt))
           (list 'scilab (change-to 'tt))
           (list 'shell (change-to 'tt))
           (list 'verbatim (change-to 'tt))
           (list 'author-name identity)
           (list 'author-email drop)
           (list 'document keep)
           (list 'quotation keep)
           (list 'theorem keep)
           (list 'proposition keep)
           (list 'corollary keep)
           (list 'lemma keep)
           (list 'proof keep)
           (list 'math identity)
           (list 'equation identity)
           (list 'equation* identity)
           (list 'concat keep)
           (list 'doc-title keep)
           (list 'section (change-to 'h2))
           (list 'subsection (change-to 'h3))
           (list 'subsubsection (change-to 'h4))
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
           (list 'big-figure parse-big-figure)
           (list 'footnote keep)
           (list 'bibliography process-bibliography)))

(define (texmacs->markdown* x)
  (cond ((not (list>0? x)) x)
        ((symbol? (car x))
         (with fun 
              (ahash-ref conversion-hash (car x))
            (if (!= fun #f)
                (fun x)
                (begin
                  (display* "Skipped " (car x) "\n")
                  (skip x)))))
        (else
         (cons (texmacs->markdown* (car x)) (texmacs->markdown* (cdr x))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public interface
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(tm-define (texmacs->markdown x)
  (if (!= (tmfile? x) #f)
      (texmacs->markdown* (tmfile? x))
      (texmacs->markdown* x)))
;;; org-tree-slide-pauses.el --- Bring the pause command from Beamer to org-tree-slide  -*- lexical-binding: t; -*-

;; Copyright 2020 cnngimenez
;;
;; Author: cnngimenez
;; Maintainer: cnngimenez
;; Version: 0.1.0
;; Keywords: convenience, org-mode, presentation
;; URL: https://github.com/cnngimenez/org-tree-slide-pauses
;; Package-Requires: ((emacs "24.5") (org-tree-slide "2.8.4"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.


;;; Commentary:

;; Bring animation like in Beamer into your org-tree-slide presentations!
;;
;; Manual installation:
;; Download the org-tree-slide-pauses.el.  Add the path to the `load-path'
;; variable and load it.  This can be added to the .emacs initialization file:
;;
;;     (add-to-list 'load-path "path-to-where-the-el-file-is")
;;     (require 'org-tree-slide-pauses)
;;
;; Usage:
;; - List items and enumerations works automatically.
;; - Add one of the following to create a pause:
;;   # pause
;;   #+pause:
;;   #+beamer: \pause
;;
;; When you start to presenting with `org-tree-slide-mode' the text between
;; pauses will appear with the "shadow" face.  Use the C->
;; (M-x `org-tree-slide-move-next-tree') to show one by one.  If there is no
;; more text to reveal, the same command will show the next slide/title like
;; usual.

;;; Code:

(provide 'org-tree-slide-pauses)
(require 'org-element)
(require 'org-tree-slide)
(require 'cl-lib)
(require 'cl-extra)
(require 'dash)
(require 'bind-key)

;;;;##########################################################################
;;;;  User Options, Variables
;;;;##########################################################################


(defconst org-tree-slide-pauses-pause-regexp "^[[:space:]]*# pause[[:space:]]*$"
  "Regexp to find the pause declaration.") ;; defconst

(defvar org-tree-slide-pauses-pause-text-list '()
  "List of overlays to hide the \"pause\" text position." )

(defvar org-tree-slide-pauses--indent-accept-first-level-only t
  "accept only the top level items when pausing")

(defvar org-tree-slide-pauses-overlay-lists '()
  "List of pauses overlays.
This list is created with the `org-tree-slide-pauses-search-pauses'.")

(defvar org-tree-slide-pauses-current-pause 0)

(defun org-tree-slide-pauses-clear-overlay-list ()
  "Clear the `org-tree-slide-pauses-overlay-lists'."
  (dolist (the-overlay org-tree-slide-pauses-overlay-lists)
    (delete-overlay the-overlay))
  (setq org-tree-slide-pauses-overlay-lists '())

  (dolist (the-overlay org-tree-slide-pauses-pause-text-list)
    (delete-overlay the-overlay))
  (setq org-tree-slide-pauses-pause-text-list '())

  (setq org-tree-slide-pauses-current-pause 0) ) ;; defun


(defun org-tree-slide-pauses--search-elements ()
  "Search all items that needs pauses and return the org-element list."
  (let ((indent-accepted 100)) ;; use a large nunmber so min calc will work
    (delq
     nil
     (org-element-map (org-element-parse-buffer nil t)
         '(comment item keyword headline)
       (lambda (element)
         "If it is one of the pauses, return their positions"
         (cond

	  ((eq (org-element-type element) 'keyword)
	   (if (or (string-equal (org-element-property :key element) "PAUSE")
		  (and (string-equal (org-element-property :key element)
				   "BEAMER")
		     (string-equal (org-element-property :value element)
				   "\\pause")))
	       element
	     nil))

	  ((eq (org-element-type element) 'comment)
	   (if (string-equal (string-trim (org-element-property :value element))
			     "pause")
	       element
	     nil))

          ((eq (org-element-type element) 'item) ;; items preceeded with - + or numbered
           (save-excursion
             (let ((prop (org-element-property :begin element)))
               (goto-char prop)
               (search-forward-regexp "[^ \\t]" nil t)
               (let ((indent (- (point) prop)))
                 ;; (message (format "%i" indent))
                 (setq indent-accepted (min indent-accepted indent))
                 (when (or (not org-tree-slide-pauses--indent-accept-first-level-only)
                          (<= indent indent-accepted))
                   element)))))

	  (t element))))))) ;; defun

(defun org-tree-slide-pauses--new-overlay-for-text ()
  "Return new overlays for all elements that needs to be hidden."

  (delq nil
	(mapcar (lambda (element)
		  (unless (member (org-element-type element)
				  '(item headline))
		    (make-overlay
		     (org-element-property :begin element)
		     (org-element-property :end element))))
		(org-tree-slide-pauses--search-elements))) ) ;; defun

(defun org-tree-slide-pauses--new-overlay-for-pair (element next-element)
  "Create overlays for a consecutive pair of (ELEMENT NEXT-ELEMENT).
Returns nil when:
- There are blanks texts between pauses (no text to show).
- The first one is a headline (no pauses between headline and first item)"
  (cond
   ((and (eq (org-element-type element) 'headline))
    ;; the first is a headline, ignore it.
    nil)

   ((and (numberp next-element)
	 (eq (org-element-type element) 'item))
    ;; It's the last and the previous is an item
    (list
     (make-overlay (org-element-property :begin element)
		   (org-element-property :end element))
     (unless (string-blank-p (buffer-substring-no-properties
			      (org-element-property :end element)
			      next-element))
       (make-overlay (org-element-property :end element) next-element))))

    ((and (numberp next-element))
     ;; It's the last and the previous is a pause
     (unless (string-blank-p (buffer-substring-no-properties
			      (org-element-property :end element)
			      next-element))
       (list (make-overlay (org-element-property :end element) next-element))))

   ((and (eq (org-element-type element) 'item)
	 (eq (org-element-type next-element) 'item))
    ;; both are items
    (list
     (make-overlay (org-element-property :begin element)
		   (org-element-property :end element))))

   ((eq (org-element-type element) 'item)
    ;; the first one is an item, the second one is a pause/headline
    (list
     (make-overlay (org-element-property :begin element)
		   (org-element-property :end element))
     (unless (string-blank-p (buffer-substring-no-properties
			      (org-element-property :end element)
			      (org-element-property :begin next-element)))
       (make-overlay (org-element-property :end element)
		     (org-element-property :begin next-element)))))

   ((eq (org-element-type next-element) 'item)
    ;; the first one is a pause/headline, the second one is an item
    (list
     (unless (string-blank-p (buffer-substring-no-properties
			      (org-element-property :end element)
			      (org-element-property :begin next-element)))
       (make-overlay (org-element-property :end element)
		     (org-element-property :begin next-element)))
     (make-overlay (org-element-property :begin next-element)
		   (org-element-property :end next-element))))

   (t
    ;; both of them are pauses
    (if (string-blank-p (buffer-substring-no-properties
			 (org-element-property :end element)
			 (org-element-property :begin next-element)))
	nil
      (list
       (make-overlay (org-element-property :end element)
		     (org-element-property :begin next-element))))) ) ;; cond
  ) ;; defun

(defun org-tree-slide-pauses--partition (lst-elements)
  "Partition of the LST-ELEMENTS into list of two elements."

  (let ((prev nil)
	(result '()))
    
    (dolist (element lst-elements)
      (setq result (append result (list (cons prev element))))
      (setq prev element))

    (when prev
      (setq result (append result (list (cons prev (point-max))))))
    
    (cdr result)) ) ;; defun


(defun org-tree-slide-pauses--new-overlay-for-pauses ()
  "Return new overlays for all elements that needs to be paused."
  (delq
   nil
   (apply #'append
	  (mapcar (lambda (element)
		    (org-tree-slide-pauses--new-overlay-for-pair (car element)
						     (cdr element)))
		  (org-tree-slide-pauses--partition
		   (org-tree-slide-pauses--search-elements))))) ) ;; defun


(defun org-tree-slide-pauses-search-pauses ()
  "Hide all pauses."
  (org-tree-slide-pauses-clear-overlay-list)

  (setq org-tree-slide-pauses-pause-text-list
	(org-tree-slide-pauses--new-overlay-for-text))
  (setq org-tree-slide-pauses-overlay-lists
	(org-tree-slide-pauses--new-overlay-for-pauses)))

(defun org-tree-slide-pauses-hide-pauses ()
  "Hide all pauses."
  (interactive)
  (dolist (the-overlay org-tree-slide-pauses-pause-text-list)
    (overlay-put the-overlay 'invisible t))
  
  (dolist (the-overlay org-tree-slide-pauses-overlay-lists)
    (overlay-put the-overlay 'face `(:foreground ,org-tree-slide-pauses--disabled-color-value))
    (org-tree-slide-pauses-all-images nil
				      (overlay-start the-overlay)
				      (overlay-end the-overlay)))) ;; defun

(defun org-tree-slide-pauses-show-pauses ()
  "Show everything to edit the buffer easily.
This do not deletes the overlays that hides the pauses commands, it only make
them visible."
  (interactive)
  (dolist (the-overlay org-tree-slide-pauses-pause-text-list)
    (overlay-put the-overlay 'invisible nil)) ) ;; defun

(defconst org-tree-slide-pauses-images-props-hidden
  '(:conversion emboss :mask heuristic)
  "What properties to add or remove when hiding or showing images." ) ;; defconst


(defun org-tree-slide-pauses-hide-image (overlay)
  "Hide the image represented by the OVERLAY.
If OVERLAY is not an image, just ignore it."
  (let ((display-props (overlay-get overlay 'display)))
    (when (and (member 'image display-props)
	       (not (cl-some
		     (lambda (elt)
		       (member elt org-tree-slide-pauses-images-props-hidden))
		     display-props)))
      (overlay-put overlay 'display
		   (append display-props
			   org-tree-slide-pauses-images-props-hidden)))))

(defun org-tree-slide-pauses-show-image (overlay)
  "Show the image represented by the OVERLAY.
If OVERLAY is not an image, just ignore it.
The image should be hidden by `org-tree-slide-pauses-hide-image'."
  (let* ((display-props (overlay-get overlay 'display))
	 (pos (cl-search org-tree-slide-pauses-images-props-hidden
			 display-props)))
    (when (and pos
	       (member 'image display-props))
      (overlay-put overlay 'display
		   (append (cl-subseq display-props 0 pos)
			   (cl-subseq display-props (+ pos (length org-tree-slide-pauses-images-props-hidden))))))))

(defun org-tree-slide-pauses-all-images (show begin end)
  "Search for overlay images between BEGIN and END points and show/hide them.
If SHOW is t, then show them."
  (cl-map nil (lambda (overlay)
	     (if show
		 (org-tree-slide-pauses-show-image overlay)
	       (org-tree-slide-pauses-hide-image overlay)))
       (overlays-in begin end)) ) ;; defun


(defun org-tree-slide-pauses-init ()
  "Search for pauses texts, create overlays and setup to start presentation.
This function is added to the `org-tree-slide-after-narrow-hook' to start the
pauses parsing."
  (org-tree-slide-pauses-search-pauses)
  (org-tree-slide-pauses-hide-pauses)
  (when (org-tree-slide-pauses--large-text-present)
    (org-tree-slide-pauses--list-fold-all))) ;; defun

(defun org-tree-slide-pauses-end ()
  "Restore the buffer and delete overlays."
  (org-tree-slide-pauses-all-images t (point-min) (point-max))
  (org-tree-slide-pauses-clear-overlay-list) ) ;; defun

(defun org-tree-slide-pauses-end-hook ()
  "This is a hook for `org-tree-slide-mode-hook' to restore the buffer.
Restore the buffer if the variable `org-tree-slide-mode' is off."
  (unless org-tree-slide-mode
    (org-tree-slide-pauses-end)) ) ;; defun

(defun org-tree-slide-pause-goto-end-pause ()
  "Show all and go directly to the last pause. Next should then jump to the next slide"
  (interactive)
  (when-let* ((lists org-tree-slide-pauses-overlay-lists)
              (lists-len (length lists))
              (steps (- lists-len org-tree-slide-pauses-current-pause)))
    (when (< 0 steps)
      (--dotimes steps
        (sit-for 0.05)
        (org-tree-slide-pauses-next-pause)))))


(defvar org-tree-slide-pauses--distance-color-values '("gray70" "gray60" "gray50"))
(defvar org-tree-slide-pauses--disabled-color-value "gray40")

(defun org-tree-slide-pauses--nth-distance-color (n)
  (or (nth n org-tree-slide-pauses--distance-color-values)
     org-tree-slide-pauses--disabled-color-value))

(defun org-tree-slide-pauses--large-text-present ()
  "is there currently a lot text to see?"
  (save-excursion
    (goto-char (point-min))
    (let ((beg (point)))
      (org-end-of-subtree)
      (< 400 (- (point) beg)))))

(defun org-tree-slide-pauses--list-fold-all ()
  "fold all list elements under this heading"
  (let ((eos (point-max)))
    (save-excursion
      (org-back-to-heading)
      (while (org-list-search-forward (org-item-beginning-re) eos t)
        (beginning-of-line 1)
        (let* ((struct (org-list-struct))
	       (prevs (org-list-prevs-alist struct))
	       (end (org-list-get-bottom-point struct)))
	  (dolist (e (org-list-get-all-items (point) struct prevs))
	    (org-list-set-item-visibility e struct 'folded))
	  (goto-char (if (< end eos) end eos)))))))

(defun org-tree-slide-pauses--list-fold (n)
  "unfold list element N (zero based)"
  (org-tree-slide-pauses--list-visibility-set n 'folded))

(defun org-tree-slide-pauses--list-unfold (n)
  "unfold list element N (zero based)"
  (org-tree-slide-pauses--list-visibility-set n 'subtree))

(defun org-tree-slide-pauses--list-visibility-set (n vis)
  "unfold list element N (zero based) of the topmost list under this heading"
  (let ((eos (point-max)))
    (save-excursion
      (org-back-to-heading)
      (when (org-list-search-forward (org-item-beginning-re) eos t)
        (beginning-of-line 1)
        (let* ((struct (org-list-struct))
	       (prevs (org-list-prevs-alist struct))
	       (end (org-list-get-bottom-point struct)))
          (let ((list-count 0))
	    (dolist (e (org-list-get-all-items (point) struct prevs))
              (when (eq list-count n)
	        (org-list-set-item-visibility e struct vis))
              (setq list-count (1+ list-count)))))))))

(defvar org-tree-slide-pauses-fold-list-age 2
  "fold lists that are ORG-TREE-SLIDE-PAUSES-FOLD-LIST-AGE - 1 behind the current pause")

(defvar org-tree-slide-pauses-before-list-unfold nil
  "A hook run before list items are unfolded on current slide")

(defvar org-tree-slide-pauses-after-list-unfold nil
  "A hook run after list items are unfolded on current slide")

(defun org-tree-slide-pauses-next-pause ()
  "Show next pause.

Basically, all text are stored as overlays in
`org-tree-slide-pauses-overlay-lists'.  Just take one more and set its face.

`org-tree-slide-pauses-current-pause' keep track of the number of overlays
displayed."

  (let* ((overlay (nth org-tree-slide-pauses-current-pause
		      org-tree-slide-pauses-overlay-lists))
        (props (org-element--get-node-properties))
        (fade-out-local-override (plist-member props ':FADING-ELEMENTS))
        (fade-out-wanted (eval (car (read-from-string (or (plist-get props ':FADING-ELEMENTS) "nil"))))))
    (when (or (and (org-tree-slide-pauses--large-text-present) (not fade-out-local-override))
             (and fade-out-local-override fade-out-wanted))
      (when (>= org-tree-slide-pauses-current-pause org-tree-slide-pauses-fold-list-age)
        (org-tree-slide-pauses--list-fold (- org-tree-slide-pauses-current-pause 2)))
      (run-hooks 'org-tree-slide-pauses-before-list-unfold)
      (org-tree-slide-pauses--list-unfold org-tree-slide-pauses-current-pause)
      (run-hooks 'org-tree-slide-pauses-after-list-unfold)
      (let ((counter 1))
        (while (>= (- org-tree-slide-pauses-current-pause counter)
                  0)
          (let ((previous-overlay (nth (- org-tree-slide-pauses-current-pause counter)
		                       org-tree-slide-pauses-overlay-lists)))
            (when previous-overlay
              (overlay-put previous-overlay 'face `(:foreground ,(org-tree-slide-pauses--nth-distance-color counter)))))
          (setq counter (1+ counter)))))
    (when overlay
      (overlay-put overlay 'face nil)
      (org-tree-slide-pauses-all-images t
					(overlay-start overlay)
					(overlay-end overlay))
      (setq org-tree-slide-pauses-current-pause
	    (1+ org-tree-slide-pauses-current-pause)))))


(defun org-tree-slide-pauses-next-advice (ots-move-next-tree &rest args)
  "Advice for 'org-tree-slide-move-next-tree'.

When the user ask for the next slide, instead show the next hidden text.
If no hidden text is found, then show the next slide (call
OTS-MOVE-NEXT-TREE, the original function with ARGS arguments)."
  (interactive)
  (if (or (>= org-tree-slide-pauses-current-pause
	    (length org-tree-slide-pauses-overlay-lists))
         (eq (point) org-tree-slide-content--pos))
      (progn
	(apply ots-move-next-tree args)
	;; Parse the current slide, or just in case the user edited the buffer
	
	;; (org-tree-slide-pauses-init)
	)
    (progn
      (org-tree-slide-pauses-next-pause)
      ;; (message "Pauses: %d/%d"
      ;;          org-tree-slide-pauses-current-pause
      ;;          (length org-tree-slide-pauses-overlay-lists))
      )) ) ;; defun

(advice-add #'org-tree-slide-move-next-tree
	    :around #'org-tree-slide-pauses-next-advice)

(add-hook 'org-tree-slide-after-narrow-before-animation-hook #'org-tree-slide-pauses-init)
(add-hook 'org-tree-slide-mode-hook #'org-tree-slide-pauses-end-hook)

(bind-key "C-M->" 'org-tree-slide-pause-goto-end-pause org-tree-slide-mode-map)

;;; org-tree-slide-pauses.el ends here

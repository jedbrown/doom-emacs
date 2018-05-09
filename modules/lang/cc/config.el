;;; lang/cc/config.el --- c, c++, and obj-c -*- lexical-binding: t; -*-

(defvar +cc-default-include-paths (list "include/")
  "A list of default paths, relative to a project root, to search for headers in
C/C++. Paths can be absolute. This is ignored if your project has a compilation
database.")

(defvar +cc-default-compiler-options
  `((c-mode . nil)
    (c++-mode
     . ,(list "-std=c++11" ; use C++11 by default
              (when IS-MAC
                ;; NOTE beware: you'll get abi-inconsistencies when passing
                ;; std-objects to libraries linked with libstdc++ (e.g. if you
                ;; use boost which wasn't compiled with libc++)
                (list "-stdlib=libc++"))))
    (objc-mode . nil))
  "A list of default compiler options for the C family. These are ignored if a
compilation database is present in the project.")


;;
;; Plugins
;;

(def-package! cc-mode
  :commands (c-mode c++-mode objc-mode java-mode)
  :mode ("\\.mm" . objc-mode)
  :preface
  (defalias 'cpp-mode 'c++-mode)

  (defun +cc-c++-header-file-p ()
    (and buffer-file-name
         (equal (file-name-extension buffer-file-name) "h")
         (or (file-exists-p (expand-file-name
                             (concat (file-name-sans-extension buffer-file-name)
                                     ".cpp")))
             (when-let* ((file (car-safe (projectile-get-other-files
                                          buffer-file-name
                                          (projectile-current-project-files)))))
               (equal (file-name-extension file) "cpp")))))

  (defun +cc-objc-header-file-p ()
    (and buffer-file-name
         (equal (file-name-extension buffer-file-name) "h")
         (re-search-forward "@\\<interface\\>" magic-mode-regexp-match-limit t)))

  (push '(+cc-c++-header-file-p  . c++-mode)  magic-mode-alist)
  (push '(+cc-objc-header-file-p . objc-mode) magic-mode-alist)

  :init
  (setq-default c-basic-offset tab-width
                c-backspace-function #'delete-backward-char
                c-default-style "doom")

  :config
  (set! :electric '(c-mode c++-mode objc-mode java-mode)
        :chars '(?\n ?\}))
  (set! :company-backend
        '(c-mode c++-mode objc-mode)
        '(company-irony-c-headers company-irony))

  ;;; Style/formatting
  ;; C/C++ style settings
  (c-toggle-electric-state -1)
  (c-toggle-auto-newline -1)

  ;;; Better fontification (also see `modern-cpp-font-lock')
  (add-hook 'c-mode-common-hook #'rainbow-delimiters-mode)
  (add-hook! (c-mode c++-mode) #'highlight-numbers-mode)
  (add-hook! (c-mode c++-mode) #'+cc|fontify-constants)

  ;; Custom style, based off of linux
  (map-put c-style-alist "doom"
           `((c-basic-offset . ,tab-width)
             (c-comment-only-line-offset . 0)
             (c-hanging-braces-alist (brace-list-open)
                                     (brace-entry-open)
                                     (substatement-open after)
                                     (block-close . c-snug-do-while)
                                     (arglist-cont-nonempty))
             (c-cleanup-list brace-else-brace)
             (c-offsets-alist
              (statement-block-intro . +)
              (knr-argdecl-intro . 0)
              (substatement-open . 0)
              (substatement-label . 0)
              (statement-cont . +)
              (case-label . +)
              ;; align args with open brace OR don't indent at all (if open brace
              ;; is at eolp and close brace is after arg with no trailing comma)
              (arglist-intro . +)
              (arglist-close +cc-lineup-arglist-close 0)
              ;; don't over-indent lambda blocks
              (inline-open . 0)
              (inlambda . 0)
              ;; indent access keywords +1 level, and properties beneath them
              ;; another level
              (access-label . -)
              (inclass +cc-c++-lineup-inclass +)
              (label . 0))))

  ;;; Keybindings
  ;; Completely disable electric keys because it interferes with smartparens and
  ;; custom bindings. We'll do this ourselves.
  (setq c-tab-always-indent nil
        c-electric-flag nil)
  (dolist (key '("#" "}" "/" "*" ";" "," ":" "(" ")" "\177"))
    (define-key c-mode-base-map key nil))
  ;; Smartparens and cc-mode both try to autoclose angle-brackets intelligently.
  ;; The result isn't very intelligent (causes redundant characters), so just do
  ;; it ourselves.
  (map! :map c++-mode-map "<" nil ">" nil)

  ;; ...and leave it to smartparens
  (sp-with-modes '(c++-mode objc-mode)
    (sp-local-pair "<" ">"
                   :when '(+cc-sp-point-is-template-p +cc-sp-point-after-include-p)
                   :post-handlers '(("| " "SPC"))))
  (sp-with-modes '(c-mode c++-mode objc-mode java-mode)
    (sp-local-pair "/*" "*/" :post-handlers '(("||\n[i]" "RET") ("| " "SPC")))
    ;; Doxygen blocks
    (sp-local-pair "/**" "*/" :post-handlers '(("||\n[i]" "RET") ("||\n[i]" "SPC")))
    (sp-local-pair "/*!" "*/" :post-handlers '(("||\n[i]" "RET") ("[d-1]< | " "SPC")))))


(def-package! modern-cpp-font-lock
  :hook (c++-mode . modern-c++-font-lock-mode))


(def-package! irony
  :commands (irony-install-server irony-mode)
  :preface
  (setq irony-server-install-prefix (concat doom-etc-dir "irony-server/"))
  :init
  (defun +cc|init-irony-mode ()
    (when (memq major-mode '(c-mode c++-mode objc-mode))
      (irony-mode +1)))
  (add-hook! (c-mode c++-mode objc-mode) #'+cc|init-irony-mode)
  :config
  (setq irony-cdb-search-directory-list '("." "build" "build-conda"))
  ;; Initialize compilation database, if present. Otherwise, fall back on
  ;; `+cc-default-compiler-options'.
  (add-hook 'irony-mode-hook #'+cc|irony-init-compile-options))

(def-package! irony-eldoc
  :hook (irony-mode . irony-eldoc))

(def-package! flycheck-irony
  :when (featurep! :feature syntax-checker)
  :after irony
  :config
  (add-hook 'irony-mode-hook #'flycheck-mode)
  (flycheck-irony-setup))


;;
;; Tools
;;

(def-package! disaster :commands disaster)


;;
;; Major modes
;;

(def-package! cmake-mode
  :mode "/CMakeLists\\.txt$"
  :mode "\\.cmake\\$"
  :config
  (set! :company-backend 'cmake-mode '(company-cmake company-yasnippet)))

(def-package! cuda-mode :mode "\\.cuh?$")

(def-package! opencl-mode :mode "\\.cl$")

(def-package! demangle-mode
  :hook llvm-mode)

(def-package! glsl-mode
  :mode "\\.glsl$"
  :mode "\\.vert$"
  :mode "\\.frag$"
  :mode "\\.geom$")


;;
;; Company plugins
;;

(def-package! company-cmake
  :when (featurep! :completion company)
  :after cmake-mode)

(def-package! company-irony
  :when (featurep! :completion company)
  :after irony)

(def-package! company-irony-c-headers
  :when (featurep! :completion company)
  :after company-irony)

(def-package! company-glsl
  :when (featurep! :completion company)
  :after glsl-mode
  :config
  (set! :company-backend 'glsl-mode '(company-glsl)))


;;
;; Rtags Support
;;

(def-package! rtags
  :commands (rtags-restart-process rtags-start-process-unless-running rtags-executable-find)
  :init
  (add-hook! (c-mode c++-mode) #'+cc|init-rtags)
  :config
  (setq rtags-autostart-diagnostics t
        rtags-use-bookmarks nil
        rtags-completions-enabled nil
        ;; If not using ivy or helm to view results, use a pop-up window rather
        ;; than displaying it in the current window...
        rtags-results-buffer-other-window t
        ;; ...and don't auto-jump to first match before making a selection.
        rtags-jump-to-first-match nil)

  (set! :lookup '(c-mode c++-mode)
    :definition #'rtags-find-symbol-at-point
    :references #'rtags-find-references-at-point)

  (add-hook 'doom-cleanup-hook #'+cc|cleanup-rtags)
  (add-hook! kill-emacs (ignore-errors (rtags-cancel-process)))

  ;; Use rtags-imenu instead of imenu/counsel-imenu
  (map! :map (c-mode-map c++-mode-map) [remap imenu] #'rtags-imenu)

  (when (featurep 'evil) (add-hook 'rtags-jump-hook #'evil-set-jump))
  (add-hook 'rtags-after-find-file-hook #'recenter))

(def-package! ivy-rtags
  :when (featurep! :completion ivy)
  :after rtags
  :config (setq rtags-display-result-backend 'ivy))

(def-package! helm-rtags
  :when (featurep! :completion helm)
  :after rtags
  :config (setq rtags-display-result-backend 'helm))

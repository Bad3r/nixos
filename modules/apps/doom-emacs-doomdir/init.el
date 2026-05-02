;;; init.el -*- lexical-binding: t; -*-

;; Minimal placeholder Doom Emacs configuration.
;; Override `programs.doom-emacs.extended.doomDir' to point at a real
;; doomdir checkout for a meaningful setup.
;;
;; `doom!' must declare at least one module group; calling it without
;; arguments errors out with "Wrong number of arguments" in
;; `doom-module-mplist-map'. Enabling the `:ui doom' module gives the
;; default Doom theme/UI without pulling in heavier feature modules.
(doom! :ui doom)

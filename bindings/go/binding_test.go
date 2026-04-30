package tree_sitter_irules_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_irules "github.com/dekobon/tree-sitter-irules/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_irules.Language())
	if language == nil {
		t.Errorf("Error loading iRules grammar")
	}
}

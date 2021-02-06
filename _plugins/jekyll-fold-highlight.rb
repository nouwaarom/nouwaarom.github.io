module Jekyll
  class FoldHighlightTagBlock < Liquid::Block
    def render(context)
      text = super
      return text.gsub("<span class=\"c1\">//FOLD</span>", "<details><summary><span class=\"c1\">...</span></summary>").gsub("<span class=\"c1\">//ENDFOLD</span>", "</details>")
    end

  end
end

Liquid::Template.register_tag('fold_highlight', Jekyll::FoldHighlightTagBlock)


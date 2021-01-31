---
layout: page
title: "Home"
permalink: /home/
---

## Posts
<ul>
  {% for post in site.posts %}
    <li>
      <a href="{{ post.url }}">{{ post.title }} - {{ post.date | date_to_string }}</a>
      {{ post.excerpt }}
    </li>
  {% endfor %}
</ul>


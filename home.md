---
layout: page
title: "Home"
permalink: /home/
---

Hi! Welcome to this little corner of the internet.
Here I write about things that are interesting to me and are worth writing about, which is mainly software.
It is not that I am only interested in software related stuff, but it's just the theme of this site.


## Posts
<ul>
  {% for post in site.posts %}
    <li>
      <a href="{{ post.url }}">{{ post.title }} - {{ post.date | date_to_string }}</a>
      {{ post.excerpt }}
    </li>
  {% endfor %}
</ul>


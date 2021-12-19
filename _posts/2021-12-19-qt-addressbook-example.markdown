---
layout: post
title:  "Qt Addressbook Improved" 
date:   2021-12-19
draft: false
description: "A more clean an consise version of the addressbook example provided with Qt. (with inline editing)"
categories: qt
---

Qt provides a lot of good examples of how the framework can be used.
While good at explaining the available functionality, the design of these examples is not optimal.
In this post I want to discuss the addressbook example, which is used to explain model/view in qt.
The adjusted code can be found at my [github](https://www.github.com/nouwaarom/Qt-Addressbook-Example).

<!--more-->

The demo application is an addressbook.
The contacts only have a name and an address.
The addressbook is sorted by alphabet.

![Screenshot](/assets/img/addressbook.png){:width="60%", .align-center}

The main classes of this example are:
- `AddressWidget`, which is a `QTabWidget` and is responsible for connecting the model and view.
- `TableModel`, which is a `QAbstractTableModel` and is responsible for keeping track of the contacts and providing data for the view.

The first thing I noticed while browsing the source is that `AddressWidget` is aware of the internals of `TableModel`.
Take a look at `AddressWidget::addEntry` for example:
{% fold_highlight %}
{% highlight c++ %}
void AddressWidget::addEntry(const QString &name, const QString &address)
{
    if (!table->getContacts().contains({ name, address })) {
        table->insertRows(0, 1, QModelIndex());

        QModelIndex index = table->index(0, 0, QModelIndex());
        table->setData(index, name, Qt::EditRole);
        index = table->index(0, 1, QModelIndex());
        table->setData(index, address, Qt::EditRole);
        removeTab(indexOf(newAddressTab));
//FOLD
    } else {
        QMessageBox::information(this, tr("Duplicate Name"),
            tr("The name \"%1\" already exists.").arg(name));
    }
}
//ENDFOLD
{% endhighlight %}
{% endfold_highlight %}
Let me try to clarify this code a bit. The property `table` holds a `TableModel`.
To add data to this model the `TableModel::insertRows` and `TableModel::setData` functions are used.
The function `TableModel::insertRows` adds a new, empty, row.
The function `TableModel::setData` sets the data for a specific row and column.
The problem with this code is that because of this `AddressWidget` needs to be aware of how `TableModel` stores it's data.
If you would decide it is better to change the columns, or add a new column in between them you would need to rewrite this code as well.
In other words, this code violates the [single-responsibiliy principle](https://en.wikipedia.org/wiki/Single-responsibility_principle).
Plus it is hard to read.

We can simplify this code by creating a `TableModel::addContact` method.
Let's look at this method and the simplifies version of `AddressWidget::addEntry`.

{% highlight c++ %}
void TableModel::addContact(const Contact& contact) {
    // The beginInsertRows and endInsertRows are used to signal updates to the view.
    beginInsertRows(QModelIndex(), 0, 0);

    contacts.insert(0, contact);

    endInsertRows();
}
{% endhighlight %}
As we can see, the `addContact` function is really clean.
The contact is added to the list of contacts and two helper functions are called in order to notify the view of the change.

{% highlight c++ %}
void AddressWidget::addEntry(const QString &name, const QString &address)
{
    if (!table->getContacts().contains({ name, address })) {
        table->addContact(Contact(name,address));
        removeTab(indexOf(newAddressTab));
    } else {
        QMessageBox::information(this, tr("Duplicate Name"),
            tr("The name \"%1\" already exists.").arg(name));
    }
}
{% endhighlight %}
In `addEntry`, we can replace the whole sequence for adding a contact with a simple call to `table->addContact`.
With this approach the internals of `TableModel` can now safely be changed without having to modify `AddressWidget` and we have created more readable code!

Now, there is a reason for using the `TableModel::setData` function. As we will see in the next post it is used to make models editable.

Thank you for reading. If you have questions or suggestions, please open an issue or mergerequest on the [repository]({{ site.repo }}) for this site.

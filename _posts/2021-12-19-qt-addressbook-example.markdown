---
layout: post
title:  "Qt TableView: Improved Addressbook Example" 
date:   2021-12-19
draft: false
description: "A more clean and consise version of the addressbook example provided with Qt. (with inline editing)"
categories: qt
---

In this post I want to discuss the Qt6 [addressbook example](https://doc.qt.io/qt-6/qtwidgets-itemviews-addressbook-example.html), which is used to explain model/view in Qt.
I will show how we can modify this example to a more maintainable architecture by decoupling the widget and the model.
The original example can be found in Qt creator.
The modified code can be found at my [GitHub](https://www.github.com/nouwaarom/Qt-Addressbook-Example).

<!--more-->

In the example, the TableView is used to implement a simple addressbook which is sorted by alphabet groups (abc-def-ghi-...). It demonstrates how a view can be sorted by a sort and filter proxy. While the code shows how to use a QTableView and QSortFilterProxyModel, the implemenation violates the [single-responsibiliy principle](https://en.wikipedia.org/wiki/Single-responsibility_principle).
In this post, we will discover how to decouple the tablemodel from the widget.

![Screenshot of the addressbook application](/assets/img/addressbook.png){:width="60%", .align-center}

The main classes of this example are:
- `AddressWidget`, which is a `QTabWidget` and is responsible for connecting the model and view.
   It creates and populates the model, creates the view and handles the menu items.
- `TableModel`, which is a `QAbstractTableModel` and is responsible for keeping track of the contacts and providing data for the view.
   To do this it provides and interface to the view from which data can be read and another interface from which data can be added to the model.
   The interface to the view consist of the functions: `rowCount`, `columnCount`, `data`, `headerData` and `flags`.
   The view will use this functions to get the data it wants to display from the model.

## Coupling between AddressWidget and TableModel
While browsing the source of `AddressWidget` we notice that `AddressWidget` is aware of the internals of `TableModel`.
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
//ENDFOLD
}
{% endhighlight %}
{% endfold_highlight %}
Let me try to clarify this code a bit. The property `table` holds a `TableModel`.
First there is a check of a contact with this data is already in the model and only if there isn't, the data is added.
To add data to this model the `TableModel::insertRows` and `TableModel::setData` functions are used.
The function `TableModel::insertRows` adds a new, empty, row.
The function `TableModel::setData` sets the data for a specific row and column. The first column contains the name and the second column contains the address.

## Why coupling is not ideal 
The problem with this code is that `AddressWidget` sets data to a specific row and column index.
This means it needs to be aware of how `TableModel` stores its data.
If you would decide it is better to change the ordering of the columns, or add a new column in between them, you would need to rewrite the `AddressWidget` as well.
The tricky thing is that these are changes to the layout.
You do not expect that a change to the layout would break editing or adding contacts, so you might not test this.
Evenmore, the code would still work because both name and address are a QString, but the behaviour is now completely different from what you intended.

In other words, this code violates the [single-responsibiliy principle](https://en.wikipedia.org/wiki/Single-responsibility_principle):
The view reposibility should be limited to the `TableModel` (the *view* model), and the `AddressWidget` should only be responsible for providing the correct data to the view model.

## Decoupling
We can simplify this code and fix the coupling by creating a `TableModel::addContact` method.
Let's look at this method and the simplified version of `AddressWidget::addEntry`.

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

Now, there is a reason for using the `TableModel::setData` function.
If a model is editable, the view uses `setData` to modify it's data.
This works really nicely and maybe I will write a short post about it, but until then you can check the [repository](https://www.github.com/nouwaarom/Qt-Addressbook-Example) for this project to see how it is used.

Thank you for reading. If you have questions or suggestions, please open an issue or mergerequest on the [repository]({{ site.repo }}) for this site.

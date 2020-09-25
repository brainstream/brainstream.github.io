---
title: "Зачем в C++ нужны безымянные пространства имён"
tags: Изучение программирования
date:   2020-09-25 21:19:05 +0300
categories: learning
---

> Все примеры в этой статье компилируются с помощью компилятора g++ в операционной системе на базе Linux. Для просмотра символов используется утилита nm, а для отладки ― gdb. В других операционных системах детали могут отличаться.

Возможно, вам уже приходилось видеть в чужом коде странные конструкции подобные этой:

```cpp
namespace {

class SomeClass
{
    // ...
};

}
```

Пространства имён (namespace) без имени называются безымянными (unnamed) или анонимными (anonymous). Прежде чем ответить на этот вопрос, нужно провести несколько практических экспериментов.

Создадим два файла: `main.cpp` и `module1.cpp`. В `module1.cpp` впишем следующий код:

```cpp
void foo() { }
```

Скомпилируем файл с помощью g++.

```
g++ -c module1.cpp
```

На выходе мы получим файл `module1.o`. Посмотрим, какие символы содержит этот файл.

```
$ nm -gC ./module1.o
0000000000000000 T foo()
```

Отлично, модуль содержит только нашу функцию `foo`. Значит мы в праве рассчитывать на то, что этот символ будет найден во время линковки. Проверим это. Впишем следующий код в файл `main.cpp`:

```cpp
void foo();

int main()
{
    foo();
    return 0;
}
```

Компиляция не вызовет ошибок. Символ `foo` будет найден в модуле `module1.cpp`.

```sh
g++ main.cpp module1.cpp -o test
```

А теперь представьте себе ситуацию, когда добавляется другой модуль, который содержит функцию с именем `foo`. Добавим файл `module2.cpp`.

```cpp
void foo() { }
```

Теперь компиляция падает.

```
$ g++ main.cpp module1.cpp module2.cpp -o test
/usr/bin/ld: /tmp/ccda7jVF.o: in function `foo()':
module2.cpp:(.text+0x0): multiple definition of `foo()'; /tmp/ccZWGcfJ.o:module1.cpp:(.text+0x0): first defined here
collect2: error: ld returned 1 exit status
```

Линкер сообщает нам, что символ `foo()` объявлен несколько раз. Так оно и есть, ведь `module2.cpp` ― это копия `module1.cpp`, а `module1.o` экспортирует символ `foo`, как мы уже выяснили. Таким образом, несмотря на то, что у нас в проекте нет ни одного заголовочного файла, функции, объявленные и реализованные в `.cpp` файлах доступны извне и конфликтуют друг с другом на этапе связывания.

Эта проблема была решена в языке C с помощью ключевого слова `static`. Модифицируйте код в `module2.cpp` таким образом:

```cpp
static void foo()
{
}
```

Теперь компиляция проходит без проблем. Давайте попробуем посмотреть на объектный код, получаемый из `module2.cpp`.

```
$ g++ -c module2.cpp 
$ nm -gC ./module2.o
```

Команда `nm` не вывела никаких результатов. Метка `static` у функции прости компилятор не выставлять наружу соответствующий символ. Значит связывание могло произойти только с реализаций из модуля `module1.cpp`. В этом легко убедиться, модифицировав код в модулях следующим образом:

*module1.cpp*

```cpp
#include <iostream>

void foo()
{
    std::cout << "Module #1\n";
}
```

*module2.cpp*

```cpp
#include <iostream>

static void foo()
{
    std::cout << "Module #2\n";
}
```

Вывод программы после компиляции ожидаемо будет таким:

```
Module #1
```

Всё, что я писал до этого относилось больше к языку C, чем к C++. Теперь перейдём к C++. Модифицируем наши модули так, чтобы в них были классы.

*module1.cpp*

```cpp
#include <iostream>

class Foo
{
public:
    void foo()
    {
        std::cout << "Module #1\n";
    }
};

void module1()
{
    Foo foo;
    foo.foo();
}
```

*module2.cpp*

```cpp
#include <iostream>

class Foo
{
public:
    void foo()
    {
        std::cout << "Module #2\n";
    }
};

void module2()
{
    Foo foo;
    foo.foo();
}
```

*main.cpp*

```cpp
void module1();
void module2();

int main()
{
    module1();
    module2();
    return 0;
}
```

В обоих модулях появился класс `Foo` с методом `foo`. Для вызова этого метода в каждом модуле объявлена функция с уникальным именем. Вопреки ожиданиям, этот код скомпилируется и слинкуется без ошибок и предупреждений. Но вот вывод вводит в ступор.

```
Module #1
Module #1
```

Попробуем скомпилировать наш проект с отладочными символами

```
g++ -g main.cpp module1.cpp module2.cpp -o test
```

и запустить в дебагере.

```
$ gdb ./test 

(gdb) start
Temporary breakpoint 1 at 0x11a9: file main.cpp, line 5.

Temporary breakpoint 1, main () at main.cpp:5
5       {
(gdb) s
6           module1();
(gdb) 
module1 () at module1.cpp:13
13      {
(gdb) 
15          foo.foo();
(gdb) 
Foo::foo (this=0x55555555537d <__libc_csu_init+77>) at module1.cpp:6
6           void foo()
(gdb) 
8               std::cout << "Module #1\n";
(gdb) 
Module #1
9           }
(gdb) 
module1 () at module1.cpp:16
16      }
(gdb) 
main () at main.cpp:7
7           module2();
(gdb) 
module2 () at module2.cpp:13
13      {
(gdb) 
15          foo.foo();
(gdb) 
Foo::foo (this=0x7fffffffdbd7) at module1.cpp:6
6           void foo()
```

Видно, что управление заходит в функцию `module2`, но вызов `Foo::foo` уходит в `module1.cpp`.

Очевидно, что линкер выбросил "лишнюю" реализацию и слинковал все вызовы `Foo::foo` с реализацией из `module1.cpp`. Это поведение зависит от компилятора и операционной системы. В среде разработчиков C++ подобное поведение принято называть неопределённым (undefined behavior).

Для исправления подобной ситуации и служат безымянные пространства имён. Поместим классы `Foo` в пространства имён и соберём проект.

*module1.cpp*

```cpp
#include <iostream>

namespace
{
    class Foo
    {
    public:
        void foo()
        {
            std::cout << "Module #1\n";
        }
    };

} // namespace

void module1()
{
    Foo foo;
    foo.foo();
}
```

*module2.cpp*

```cpp
#include <iostream>

namespace
{
    class Foo
    {
    public:
        void foo()
        {
            std::cout << "Module #2\n";
        }
    };

} // namespace

void module2()
{
    Foo foo;
    foo.foo();
}
```

Вывод программы теперь именно такой, каким должен быть.

```
Module #1
Module #2
```

Анонимные пространства имён ― это рекомендованный способ избежать коллизий. Используйте его для всех объявлений внутри файлов `*.cpp`. В том числе вместо ключевого слова `static`, о котором речь шла выше.

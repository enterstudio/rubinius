#ifndef RBX_BUILTIN_LIST_HPP
#define RBX_BUILTIN_LIST_HPP

#include "builtin/object.hpp"
#include "type_info.hpp"

namespace rubinius {

  class ListNode : public Object {
  public:
    const static size_t fields = 2;
    const static object_type type = ListNodeType;

  private:
    OBJECT object_;  // slot
    ListNode* next_; // slot

  public:
    /* accessors */

    attr_accessor(object, Object);
    attr_accessor(next, ListNode);

    /* interface */

    class Info : public TypeInfo {
    public:
      BASIC_TYPEINFO(TypeInfo)
    };

  };

  class List : public Object {
  public:
    const static size_t fields = 3;
    const static object_type type = ListType;

  private:
    INTEGER count_;   // slot
    ListNode* first_; // slot
    ListNode* last_;  // slot

  public:
    /* accessors */

    attr_accessor(count, Integer);
    attr_accessor(first, ListNode);
    attr_accessor(last, ListNode);

    /* interface */

    bool empty_p();
    size_t size();
    static void init(STATE);
    static List* create(STATE);
    void append(STATE, OBJECT obj);
    OBJECT shift(STATE);
    OBJECT locate(STATE, size_t index);
    size_t remove(STATE, OBJECT obj);

    class Info : public TypeInfo {
    public:
      BASIC_TYPEINFO(TypeInfo)
    };

  };

};
#endif

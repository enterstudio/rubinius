#include "builtin/dir.hpp"
#include "ffi.hpp"
#include "vm.hpp"
#include "objectmemory.hpp"
#include "builtin/array.hpp"
#include "builtin/class.hpp"
#include "builtin/fixnum.hpp"
#include "builtin/memorypointer.hpp"
#include "builtin/string.hpp"

#include <sys/types.h>
#include <dirent.h>

namespace rubinius {
  void Dir::init(STATE) {
    GO(dir).set(state->new_class("Dir", G(object), Dir::fields));
    G(dir)->set_object_type(state, DirType);
  }

  Dir* Dir::create(STATE) {
    Dir* d = (Dir*)state->om->new_object(G(dir), Dir::fields);
    d->data(state, (MemoryPointer*)Qnil);

    return d;
  }

  void Dir::guard(STATE) {
    // TODO: raise IOError, "closed directory" (RAISE_FROM_ERRNO)
    if(data_->nil_p()) {
      throw std::runtime_error("dir->data is nil");
    }
  }

  OBJECT Dir::open(STATE, String* path) {
    DIR* d = opendir(path->c_str());

    if(!d) state->raise_from_errno("Unable to open directory");
    data(state, MemoryPointer::create(state, d));

    return Qnil;
  }

  OBJECT Dir::close(STATE) {
    guard(state);

    DIR* d = (DIR*)data_->pointer;
    if(d) {
      data(state, (MemoryPointer*)Qnil);
      closedir(d);
      return Qtrue;
    }

    return Qfalse;
  }

  OBJECT Dir::closed_p(STATE) {
    return data_->nil_p() ? Qtrue : Qfalse;
  }

  OBJECT Dir::read(STATE) {
    guard(state);

    DIR* d = (DIR*)data_->pointer;
    struct dirent *ent = readdir(d);

    if(!ent) return Qnil;

    return String::create(state, ent->d_name);
  }

  OBJECT Dir::control(STATE, FIXNUM kind, INTEGER pos) {
    guard(state);

    DIR* d = (DIR*)data_->pointer;

    switch(kind->to_native()) {
    case 0:
      seekdir(d, pos->to_native());
      return Qtrue;
    case 1:
      rewinddir(d);
      return Qtrue;
    case 2:
      return Integer::from(state, telldir(d));
    }
    return Qnil;
  }
}

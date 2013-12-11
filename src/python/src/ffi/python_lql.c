/* Copyright (c) 2011, Diego Souza                                                 */
/* All rights reserved.                                                            */
                                                                                   
/* Redistribution and use in source and binary forms, with or without              */
/* modification, are permitted provided that the following conditions are met:     */
                                                                                   
/*   * Redistributions of source code must retain the above copyright notice,      */
/*     this list of conditions and the following disclaimer.                       */
/*   * Redistributions in binary form must reproduce the above copyright notice,   */
/*     this list of conditions and the following disclaimer in the documentation   */
/*     and/or other materials provided with the distribution.                      */
/*   * Neither the name of the <ORGANIZATION> nor the names of its contributors    */
/*     may be used to endorse or promote products derived from this software       */
/*     without specific prior written permission.                                  */

/* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND */
/* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED   */
/* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE          */
/* DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE    */
/* FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL      */
/* DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR      */
/* SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER      */
/* CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,   */
/* OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE   */
/* OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.            */

#include <Python.h>
#include "python_lql.h"
#include "python_naming.h"
#include "python_endpoint.h"

PyTypeObject pylql_context_type = { PyObject_HEAD_INIT(NULL) };
PyTypeObject pylql_cursor_type  = { PyObject_HEAD_INIT(NULL) };

static
PyObject *pylql_context_init(PyTypeObject *, PyObject *, PyObject *);

static
PyObject *pylql_context_close(PyObject *, PyObject *);

static
PyObject *pylql_context_cursor(PyObject *, PyObject *);

static
PyObject *pylql_cursor_init(PyTypeObject *, PyObject *, PyObject *);

static
PyObject *pylql_cursor_close(PyObject *, PyObject *);

static
PyObject *pylql_cursor_execute(PyObject *, PyObject *);

static
void pylql_context_free(PyObject *);

static
void pylql_cursor_free(PyObject *);

static
PyObject *__pyendpoint_type()
{
  PyObject *pyendpoint = PyImport_ImportModule("_leela_endpoint");
  if (pyendpoint == NULL)
  { return(NULL); }

  PyObject *pyendpoint_type = PyObject_GetAttrString(pyendpoint, "Endpoint");
  Py_DECREF(pyendpoint);
  return(pyendpoint_type);
}

static
PyMethodDef pylql_context_methods[] = {
  {"close", pylql_context_close, METH_VARARGS,
   NULL
  },
  {"cursor", pylql_context_cursor, METH_VARARGS,
   NULL
  },
  {NULL}
};

static
PyMethodDef pylql_cursor_methods[] = {
  {"close", pylql_cursor_close, METH_VARARGS,
   NULL
  },
  {"execute", pylql_cursor_execute, METH_VARARGS,
   NULL,
  },
  {NULL}
};

PyMODINIT_FUNC
init_leela_lql(void)
{
  pylql_context_type.tp_basicsize = sizeof(pylql_context_t);
  pylql_context_type.tp_flags     = Py_TPFLAGS_DEFAULT;
  pylql_context_type.tp_name      = "_leela_lql.Context";
  pylql_context_type.tp_methods   = pylql_context_methods;
  pylql_context_type.tp_dealloc   = pylql_context_free;
  pylql_context_type.tp_new       = pylql_context_init;

  pylql_cursor_type.tp_basicsize = sizeof(pylql_cursor_t);
  pylql_cursor_type.tp_flags     = Py_TPFLAGS_DEFAULT;
  pylql_cursor_type.tp_name      = "_leela_lql.Cursor";
  pylql_cursor_type.tp_methods   = pylql_cursor_methods;
  pylql_cursor_type.tp_dealloc   = pylql_cursor_free;
  pylql_cursor_type.tp_new       = pylql_cursor_init;

  if (PyType_Ready(&pylql_context_type) != 0)
  { return; }
  Py_INCREF(&pylql_context_type);

  if (PyType_Ready(&pylql_cursor_type) != 0)
  { return; }
  Py_INCREF(&pylql_cursor_type);

  PyObject *m = Py_InitModule("_leela_lql", NULL);
  PyModule_AddObject(m, "Context", (PyObject *) &pylql_context_type);
  PyModule_AddObject(m, "Cursor", (PyObject *) &pylql_cursor_type);
}

PyObject *pylql_context_init(PyTypeObject *type, PyObject *args, PyObject *kwargs)
{
  (void) kwargs;
  PyObject *pytype;
  const char *path;
  pyleela_endpoint_t *endpoint;

  pytype = __pyendpoint_type();
  if (pytype == NULL)
  { return(NULL); }

  pylql_context_t *self = (pylql_context_t *) type->tp_alloc(type, 0);
  if (self != NULL)
  {
    self->context = NULL;
    if (! PyArg_ParseTuple(args, "O!s", pytype, &endpoint, &path))
    {
      Py_DECREF(self);
      return(NULL);
    }

    self->context = leela_lql_context_init(endpoint->endpoint, path);
    if (self->context == NULL)
    {
      Py_DECREF(self);
      PyErr_SetString(PyExc_RuntimeError, "parse error");
      return(NULL);
    }
  }

  return((PyObject *) self);
}

PyObject *pylql_cursor_init(PyTypeObject *type, PyObject *args, PyObject *kwargs)
{
  (void) kwargs;
  int timeout;
  const char *secret;
  const char *username;
  pylql_context_t *context;

  pylql_cursor_t *self = (pylql_cursor_t *) type->tp_alloc(type, 0);
  if (self != NULL)
  {
    self->cursor = NULL;
    if (! PyArg_ParseTuple(args, "O!ssi", &pylql_context_type, &context, &username, &secret, &timeout))
    {
      Py_DECREF(self);
      return(NULL);
    }

    self->cursor = leela_lql_cursor_init(context->context, username, secret, timeout);
    if (self->cursor == NULL)
    {
      Py_DECREF(self);
      PyErr_SetString(PyExc_RuntimeError, "parse error");
      return(NULL);
    }
  }

  return((PyObject *) self);
}

PyObject *pylql_context_close(PyObject *self, PyObject *args)
{
  (void) args;
  pylql_context_t *context = (pylql_context_t *) self;
  leela_lql_context_close(context->context);
  context->context = NULL;
  Py_RETURN_NONE;
}

PyObject *pylql_cursor_close(PyObject *self, PyObject *args)
{
  (void) args;
  pylql_cursor_t *cursor = (pylql_cursor_t *) self;
  leela_lql_cursor_close(cursor->cursor);
  cursor->cursor = NULL;
  Py_RETURN_NONE;
}

void pylql_cursor_free(PyObject *self)
{ self->ob_type->tp_free(self); }

PyObject *pylql_context_cursor(PyObject *self, PyObject *args)
{
  int timeout;
  const char *secret;
  const char *username;

  if (!PyArg_ParseTuple(args, "ssi", &username, &secret, &timeout))
  { return(NULL); }

  PyObject *myargs = Py_BuildValue("Ossi", self, username, secret, timeout);
  if (myargs == NULL)
  { return(NULL); }

  PyObject *result = pylql_cursor_init(&pylql_cursor_type, myargs, NULL);
  Py_DECREF(myargs);
  return(result);
}

PyObject *pylql_cursor_execute(PyObject *self, PyObject *args)
{
  const char *query;
  pylql_cursor_t *cursor = (pylql_cursor_t *) self;

  if (! PyArg_ParseTuple(args, "s", &query))
  { return(NULL); }

  leela_status rc = leela_lql_cursor_execute(cursor->cursor, query);
  if (rc == LEELA_OK)
  { Py_RETURN_NONE; }

  PyErr_SetString(PyExc_RuntimeError, "could not execute query!");
  return(NULL);
}

void pylql_context_free(PyObject *self)
{ self->ob_type->tp_free(self); }

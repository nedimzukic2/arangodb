//
// IResearch search engine 
// 
// Copyright (c) 2016 by EMC Corporation, All Rights Reserved
// 
// This software contains the intellectual property of EMC Corporation or is licensed to
// EMC Corporation from third parties. Use of this software and the intellectual property
// contained therein is expressly limited to the terms and conditions of the License
// Agreement under which it is provided by or on behalf of EMC.
// 

#ifndef IRESEARCH_INDEX_READER_H
#define IRESEARCH_INDEX_READER_H

#include "store/directory.hpp"
#include "store/directory_attributes.hpp"
#include "utils/string.hpp"
#include "formats/formats.hpp"
#include "utils/memory.hpp"
#include "utils/iterator.hpp"

#include <vector>
#include <numeric>
#include <functional>

NS_ROOT

/* -------------------------------------------------------------------
* index_reader
* ------------------------------------------------------------------*/

struct sub_reader;

struct IRESEARCH_API index_reader {
  DECLARE_SPTR(index_reader);
  DECLARE_FACTORY(index_reader);

  typedef std::function<bool(const field_meta&, data_input&)> document_visitor_f;
  typedef forward_iterator_impl<sub_reader> reader_iterator_impl;
  typedef forward_iterator<reader_iterator_impl> reader_iterator;

  virtual ~index_reader();

  // number of live documents
  virtual uint64_t live_docs_count() const = 0;

  // number of live documents for the specified field
  virtual uint64_t docs_count(const string_ref& field) const = 0;

  // total number of documents including deleted
  virtual uint64_t docs_count() const = 0;

  // first sub-segment
  virtual reader_iterator begin() const = 0;

  // after the last sub-segment
  virtual reader_iterator end() const = 0;

  // returns number of sub-segments in current reader
  virtual size_t size() const = 0;
}; // index_reader

/* -------------------------------------------------------------------
* sub_reader
* ------------------------------------------------------------------*/

struct IRESEARCH_API sub_reader : index_reader {
  typedef iresearch::iterator<doc_id_t> docs_iterator_t;

  DECLARE_SPTR(sub_reader);
  DECLARE_FACTORY(sub_reader);

  using index_reader::docs_count;

  // returns number of live documents by the specified field
  virtual uint64_t docs_count(const string_ref& field) const {
    const term_reader* rdr = this->field(field);
    return nullptr == rdr ? 0 : rdr->docs_count();
  }

  // returns iterator over the live documents in current segment
  virtual docs_iterator_t::ptr docs_iterator() const = 0;

  virtual field_iterator::ptr fields() const = 0;

  // returns corresponding term_reader by the specified field
  virtual const term_reader* field(
    const string_ref& field
  ) const = 0;

  virtual column_iterator::ptr columns() const = 0;

  virtual const column_meta* column(const string_ref& name) const = 0;

  // returns corresponding column reader by the specified field
  virtual columnstore_reader::values_reader_f values(field_id id) const = 0;

  virtual bool visit(
    field_id id,
    const columnstore_reader::values_visitor_f& reader
  ) const = 0;

  columnstore_reader::values_reader_f values(const string_ref& field) const;

  bool visit(
    const string_ref& name,
    const columnstore_reader::values_visitor_f& reader
  ) const;
}; // sub_reader

NS_END

MSVC_ONLY(template class IRESEARCH_API std::function<bool(iresearch::doc_id_t)>); // sub_reader::value_visitor_f

NS_ROOT

// -------------------------------------------------------------------
// composite_reader
// -------------------------------------------------------------------

class IRESEARCH_API composite_reader: public index_reader {
 public:
  DECLARE_SPTR(composite_reader);

  // return the i'th sub_reader
  virtual const sub_reader& operator[](size_t i) const = 0;

  // return the base doc_id for the i'th sub_reader
  virtual doc_id_t base(size_t i) const = 0;
};

NS_END

#endif